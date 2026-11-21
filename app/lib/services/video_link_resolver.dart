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
            const {'mp4', 'm4v', 'mov', 'webm'}.contains(extension));
  }
}

class VideoLinkResolver {
  VideoLinkResolver._();

  static const _mediaExtensions = {
    'mp4', 'm4v', 'mov', 'webm', 'm3u8'
  };
  static final http.Client _client = http.Client();

  static Future<ResolvedVideoSource> resolve(String rawUrl) => _resolve(rawUrl, 0, null);

  static Future<ResolvedVideoSource> _resolve(String rawUrl, int depth, Uri? referer) async {
    final pageUri = Uri.tryParse(rawUrl.trim());
    if (pageUri == null ||
        pageUri.scheme != 'https' ||
        pageUri.host.isEmpty ||
        pageUri.userInfo.isNotEmpty) {
      throw const FormatException('Please enter a valid HTTPS webpage or video URL.');
    }

    final extension = _extension(pageUri);
    if (_mediaExtensions.contains(extension)) {
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
    final inScript = _findMediaInText(response.body);
    if (inScript != null) return inScript;

    // One level of embedded players (iframes), opened like a normal browser would.
    if (depth == 0) {
      var tried = 0;
      for (final frame in document.querySelectorAll('iframe[src], iframe[data-src]')) {
        final src = (frame.attributes['src'] ?? frame.attributes['data-src'] ?? '').trim();
        if (src.isEmpty || src.startsWith('about:') || src.startsWith('javascript:')) continue;
        if (tried++ >= 3) break;
        try {
          return await _resolve(pageUri.resolve(src).toString(), 1, pageUri);
        } catch (_) {
          // Try the next embedded player.
        }
      }
    }

    throw const FormatException(
      'No directly playable video was found on this page. The site may use an unsupported player, require sign-in, or protect its stream.',
    );
  }

  static ResolvedVideoSource? _findMediaInText(String text) {
    final cleaned = text
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll('&amp;', '&');
    final re = RegExp(
        r'''https?://[^"'\s<>\\]+?\.(?:mp4|m3u8|webm|m4v)(?:\?[^"'\s<>\\]*)?''',
        caseSensitive: false);
    for (final m in re.allMatches(cleaned)) {
      var url = m.group(0)!;
      if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) continue;
      final ext = _extension(uri);
      if (!_mediaExtensions.contains(ext)) continue;
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
