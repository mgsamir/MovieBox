import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class ResolvedVideoSource {
  final Uri uri;
  final String contentType;

  const ResolvedVideoSource({required this.uri, required this.contentType});

  bool get isHls =>
      uri.path.toLowerCase().endsWith('.m3u8') ||
      contentType.toLowerCase().contains('mpegurl');

  bool get canDownload {
    final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = segment.lastIndexOf('.');
    final extension = dot < 0 ? '' : segment.substring(dot + 1).toLowerCase();
    return !isHls &&
        (contentType.toLowerCase().startsWith('video/') ||
            const {'mp4', 'm4v', 'mov', 'webm', 'mkv'}.contains(extension));
  }
}

/// One downloadable or playable file found on a page, with what could be
/// told about it (language and quality come from labels and file names).
class MediaOption {
  final ResolvedVideoSource source;
  final String? language; // null = original audio
  final int? height;
  final int? sizeBytes;
  const MediaOption({required this.source, this.language, this.height, this.sizeBytes});

  Uri get uri => source.uri;
  bool get canDownload => source.canDownload;
  String get languageLabel =>
      language == null ? 'Original Audio' : (language == 'English' ? 'English' : '$language dub');
  String get qualityLabel => height == null ? (source.isHls ? 'Stream' : 'Video') : '${height}P';
  MediaOption withSize(int? bytes) =>
      MediaOption(source: source, language: language, height: height, sizeBytes: bytes);
}

class _RawMedia {
  final Uri uri;
  String label;
  _RawMedia(this.uri, this.label);
}

class VideoLinkResolver {
  VideoLinkResolver._();

  static const _languageNames = {
    'hindi': 'Hindi', 'tamil': 'Tamil', 'telugu': 'Telugu', 'malayalam': 'Malayalam',
    'kannada': 'Kannada', 'bengali': 'Bengali', 'punjabi': 'Punjabi', 'marathi': 'Marathi',
    'english': 'English', 'spanish': 'Spanish', 'portuguese': 'Portuguese',
    'french': 'French', 'japanese': 'Japanese', 'korean': 'Korean',
  };
  static final _mediaRegex = RegExp(
      r'''https?://[^"'\s<>\\]+?\.(?:mp4|m3u8|webm|m4v|mkv)(?:\?[^"'\s<>\\]*)?''',
      caseSensitive: false);

  static int? _heightOf(String text) {
    final t = text.toLowerCase();
    final m = RegExp(r'(?<![0-9])(2160|1440|1080|720|576|480|360|240)\s*p').firstMatch(t);
    if (m != null) return int.parse(m.group(1)!);
    if (RegExp(r'(?<![a-z0-9])(4k|uhd)(?![a-z0-9])').hasMatch(t)) return 2160;
    return null;
  }

  static String? _languageOf(String text) {
    final t = text.toLowerCase();
    for (final e in _languageNames.entries) {
      if (t.contains(e.key)) return e.value;
    }
    return null;
  }

  /// Every video file the page (and the site's own download pages) offers,
  /// with language, quality and size, so the user can choose what to download.
  static Future<List<MediaOption>> resolveAll(String rawUrl) async {
    final raw = <String, _RawMedia>{};
    await _collect(rawUrl, 0, null, '', raw, <String>{});

    final options = <MediaOption>[];
    final taken = <String>{};
    for (final r in raw.values) {
      final ext = _extension(r.uri);
      final source = ResolvedVideoSource(
        uri: r.uri,
        contentType: ext == 'm3u8' ? 'application/vnd.apple.mpegurl' : 'video/$ext',
      );
      final name = r.uri.pathSegments.isEmpty ? '' : r.uri.pathSegments.last;
      final text = '${r.label} $name';
      final height = _heightOf(text);
      final language = _languageOf(text);
      // Mirrors of the same quality and language: keep the first.
      if (height != null && !taken.add('${language ?? ''}|$height|${source.isHls}')) continue;
      options.add(MediaOption(source: source, language: language, height: height));
    }

    final sized = List<MediaOption>.from(await Future.wait(options.take(16).map((o) async {
      if (o.source.isHls) return o;
      try {
        final head = await _client
            .head(o.uri, headers: const {'User-Agent': 'MovieBox Android'})
            .timeout(const Duration(seconds: 6));
        return o.withSize(int.tryParse(head.headers['content-length'] ?? ''));
      } catch (_) {
        return o;
      }
    })));
    sized.sort((a, b) {
      final l = (a.language ?? '').compareTo(b.language ?? '');
      return l != 0 ? l : (b.height ?? 0).compareTo(a.height ?? 0);
    });
    return sized;
  }

  static Future<void> _collect(String rawUrl, int depth, Uri? referer, String hint,
      Map<String, _RawMedia> out, Set<String> seen) async {
    final pageUri = Uri.tryParse(rawUrl.trim());
    if (pageUri == null ||
        pageUri.scheme != 'https' ||
        pageUri.host.isEmpty ||
        pageUri.userInfo.isNotEmpty) {
      return;
    }
    if (seen.length > 12 || !seen.add(pageUri.toString())) return;

    void add(Uri uri, String label) {
      if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return;
      if (!_mediaExtensions.contains(_extension(uri))) return;
      final text = '$hint $label'.trim();
      final old = out[uri.toString()];
      if (old == null) {
        out[uri.toString()] = _RawMedia(uri, text);
      } else if (text.length > old.label.length) {
        old.label = text;
      }
    }

    if (_mediaExtensions.contains(_extension(pageUri))) {
      add(pageUri, '');
      return;
    }

    http.Response response;
    try {
      response = await _client.get(pageUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
        if (referer != null) 'Referer': referer.toString(),
      }).timeout(const Duration(seconds: 20));
    } catch (_) {
      return;
    }
    final type = response.headers['content-type']?.toLowerCase() ?? '';
    if (response.statusCode < 200 || response.statusCode >= 400) return;
    if (!type.contains('html') || response.bodyBytes.length > 2 * 1024 * 1024) return;

    final document = html_parser.parse(utf8.decode(response.bodyBytes, allowMalformed: true));

    for (final el in document.querySelectorAll('video[src], video source[src], source[src]')) {
      final src = el.attributes['src']?.trim();
      if (src == null || src.isEmpty) continue;
      final parts = <String>[
        for (final k in const ['label', 'title', 'res', 'data-res', 'data-quality', 'data-lang', 'srclang'])
          if (el.attributes[k] != null) el.attributes[k]!,
      ];
      final size = (el.attributes['size'] ?? '').trim();
      if (RegExp(r'^\d{3,4}$').hasMatch(size)) parts.add('${size}p');
      add(pageUri.resolve(src), parts.join(' '));
    }

    final follow = <MapEntry<String, String>>[];
    for (final a in document.querySelectorAll('a[href]')) {
      final href = a.attributes['href']?.trim() ?? '';
      if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) continue;
      final target = pageUri.resolve(href);
      final text = '${a.text} ${a.attributes['title'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (_mediaExtensions.contains(_extension(target))) {
        add(target, text);
        continue;
      }
      final lower = '${text.toLowerCase()} ${href.toLowerCase()}';
      if (depth == 0 &&
          target.scheme == 'https' &&
          target.host == pageUri.host &&
          target != pageUri &&
          (lower.contains('download') || _heightOf(lower) != null)) {
        follow.add(MapEntry(target.toString(), text));
      }
    }

    final cleaned = response.body
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll('&amp;', '&');
    for (final m in _mediaRegex.allMatches(cleaned)) {
      final uri = Uri.tryParse(m.group(0)!.replaceFirst('http://', 'https://'));
      if (uri != null) add(uri, '');
    }

    if (depth == 0) {
      final frames = <String>[];
      for (final fr in document.querySelectorAll('iframe[src], iframe[data-src]')) {
        final src = (fr.attributes['src'] ?? fr.attributes['data-src'] ?? '').trim();
        if (src.isEmpty || src.startsWith('about:') || src.startsWith('javascript:')) continue;
        frames.add(pageUri.resolve(src).toString());
      }
      await Future.wait([
        for (final f in follow.take(8)) _collect(f.key, 1, pageUri, f.value, out, seen),
        for (final f in frames.take(3)) _collect(f, 1, pageUri, hint, out, seen),
      ]);
    }
  }

  static const _mediaExtensions = {
    'mp4', 'm4v', 'mov', 'webm', 'mkv', 'm3u8'
  };
  static final http.Client _client = http.Client();

  /// With [forDownload] only real files are returned (streams such as .m3u8
  /// are skipped), and the site's own "download" pages are followed one level.
  static Future<ResolvedVideoSource> resolve(String rawUrl, {bool forDownload = false}) =>
      _resolve(rawUrl, 0, null, forDownload);

  static Future<ResolvedVideoSource> _resolve(
      String rawUrl, int depth, Uri? referer, bool forDownload) async {
    final pageUri = Uri.tryParse(rawUrl.trim());
    if (pageUri == null ||
        pageUri.scheme != 'https' ||
        pageUri.host.isEmpty ||
        pageUri.userInfo.isNotEmpty) {
      throw const FormatException('Please enter a valid HTTPS webpage or video URL.');
    }

    final extension = _extension(pageUri);
    if (_mediaExtensions.contains(extension) && !(forDownload && extension == 'm3u8')) {
      return ResolvedVideoSource(
        uri: pageUri,
        contentType: extension == 'm3u8'
            ? 'application/vnd.apple.mpegurl'
            : 'video/$extension',
      );
    }

    // Some legitimate CDN video URLs do not have a file extension.
    try {
      final head = await _client.head(pageUri,
          headers: const {'User-Agent': 'MovieBox Android'}).timeout(
        const Duration(seconds: 12),
      );
      final type = head.headers['content-type']?.split(';').first.trim() ?? '';
      if (head.statusCode >= 200 &&
          head.statusCode < 400 &&
          (type.toLowerCase().startsWith('video/') ||
              type.toLowerCase().contains('mpegurl'))) {
        return ResolvedVideoSource(uri: head.request?.url ?? pageUri, contentType: type);
      }
    } catch (_) {
      // Continue with normal webpage inspection if HEAD is unsupported.
    }

    final response = await _client.get(
      pageUri,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
        if (referer != null) 'Referer': referer.toString(),
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw FormatException('The webpage could not be opened (HTTP ${response.statusCode}).');
    }

    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.startsWith('video/') || contentType.contains('mpegurl')) {
      return ResolvedVideoSource(
        uri: response.request?.url ?? pageUri,
        contentType: contentType,
      );
    }
    if (!contentType.contains('html') && !contentType.contains('xhtml')) {
      throw const FormatException('This link does not return a playable video or webpage.');
    }

    // Avoid parsing unexpectedly huge pages.
    if (response.bodyBytes.length > 2 * 1024 * 1024) {
      throw const FormatException('This webpage is too large to inspect safely.');
    }

    final document = html_parser.parse(utf8.decode(response.bodyBytes, allowMalformed: true));
    final candidates = <String>[];

    for (final element in document.querySelectorAll('video[src], video source[src], source[src]')) {
      final src = element.attributes['src'];
      if (src != null && src.trim().isNotEmpty) candidates.add(src.trim());
    }
    for (final element in document.querySelectorAll(
        'meta[property="og:video"], meta[property="og:video:url"], meta[name="twitter:player:stream"]')) {
      final src = element.attributes['content'];
      if (src != null && src.trim().isNotEmpty) candidates.add(src.trim());
    }

    // Plain links to a video file (for example a "Download" button).
    for (final a in document.querySelectorAll('a[href]')) {
      final href = a.attributes['href']?.trim();
      if (href == null || href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) continue;
      final ext = _extension(pageUri.resolve(href));
      if (_mediaExtensions.contains(ext)) candidates.add(href);
    }

    // JSON-LD can expose a publisher's actual media URL as contentUrl.
    for (final script in document.querySelectorAll('script[type="application/ld+json"]')) {
      final raw = script.text.trim();
      if (raw.isEmpty) continue;
      try {
        _collectContentUrls(jsonDecode(raw), candidates);
      } catch (_) {
        // Ignore malformed structured data and continue with HTML sources.
      }
    }

    for (final candidate in candidates) {
      final uri = pageUri.resolve(candidate);
      if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
        continue;
      }
      final ext = _extension(uri);
      if (_mediaExtensions.contains(ext)) {
        if (forDownload && ext == 'm3u8') continue;
        return ResolvedVideoSource(
          uri: uri,
          contentType: ext == 'm3u8'
              ? 'application/vnd.apple.mpegurl'
              : 'video/$ext',
        );
      }
      // Verify extension-less media URLs without downloading their contents.
      try {
        final head = await _client.head(uri,
            headers: const {'User-Agent': 'MovieBox Android'}).timeout(
          const Duration(seconds: 8),
        );
        final type = head.headers['content-type']?.split(';').first.trim() ?? '';
        if (head.statusCode >= 200 &&
            head.statusCode < 400 &&
            (type.toLowerCase().startsWith('video/') ||
                type.toLowerCase().contains('mpegurl'))) {
          return ResolvedVideoSource(uri: head.request?.url ?? uri, contentType: type);
        }
      } catch (_) {
        // Try the next public media candidate.
      }
    }

    // Many players keep the file address inside inline scripts or JSON.
    final inScript = _findMediaInText(response.body, forDownload);
    if (inScript != null) return inScript;

    // One level deeper: embedded players (iframes) and, for downloads, the
    // site's own "download" pages. Opened like a normal browser would.
    if (depth == 0) {
      final frames = <String>[];
      for (final frame in document.querySelectorAll('iframe[src], iframe[data-src]')) {
        final src = (frame.attributes['src'] ?? frame.attributes['data-src'] ?? '').trim();
        if (src.isEmpty || src.startsWith('about:') || src.startsWith('javascript:')) continue;
        frames.add(pageUri.resolve(src).toString());
      }
      final downloads = <String>[];
      for (final a in document.querySelectorAll('a[href]')) {
        final href = a.attributes['href']?.trim() ?? '';
        if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) continue;
        if (!(a.text.toLowerCase().contains('download') || href.toLowerCase().contains('download'))) continue;
        final target = pageUri.resolve(href);
        if (target.scheme != 'https' || target.host != pageUri.host || target == pageUri) continue;
        if (!downloads.contains(target.toString())) downloads.add(target.toString());
      }
      final follow = forDownload ? [...downloads, ...frames] : [...frames, ...downloads];
      var tried = 0;
      for (final next in follow) {
        if (tried++ >= 4) break;
        try {
          return await _resolve(next, 1, pageUri, forDownload);
        } catch (_) {
          // Try the next one.
        }
      }
    }

    throw const FormatException(
      'No directly playable video was found on this page. The site may use an unsupported player, require sign-in, or protect its stream.',
    );
  }

  static ResolvedVideoSource? _findMediaInText(String text, bool forDownload) {
    final cleaned = text
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll('&amp;', '&');
    final re = RegExp(
        r'''https?://[^"'\s<>\\]+?\.(?:mp4|m3u8|webm|m4v|mkv)(?:\?[^"'\s<>\\]*)?''',
        caseSensitive: false);
    for (final m in re.allMatches(cleaned)) {
      var url = m.group(0)!;
      if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) continue;
      final ext = _extension(uri);
      if (!_mediaExtensions.contains(ext)) continue;
      if (forDownload && ext == 'm3u8') continue;
      return ResolvedVideoSource(
        uri: uri,
        contentType: ext == 'm3u8' ? 'application/vnd.apple.mpegurl' : 'video/$ext',
      );
    }
    return null;
  }

  static String _extension(Uri uri) {
    final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = segment.lastIndexOf('.');
    return dot < 0 ? '' : segment.substring(dot + 1).toLowerCase();
  }

  static void _collectContentUrls(dynamic value, List<String> output) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key.toString().toLowerCase() == 'contenturl' &&
            entry.value is String) {
          output.add((entry.value as String).trim());
        } else {
          _collectContentUrls(entry.value, output);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        _collectContentUrls(item, output);
      }
    }
  }
}
