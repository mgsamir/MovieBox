import 'dart:async';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// One downloadable (or stream-only) version of a title: language + quality.
class MediaOption {
  final String url;
  final String quality; // 480P, 1080P, 2160P or "Standard"
  final int height; // 0 when unknown, used for sorting
  final String language; // "Hindi dub", "Original audio", ...
  final String ext;
  int? bytes;

  MediaOption({
    required this.url,
    required this.quality,
    required this.height,
    required this.language,
    required this.ext,
  });

  bool get isStream => ext == 'm3u8';
  String get sizeText => bytes == null ? 'Size unknown' : formatBytes(bytes!);
}

String formatBytes(int b) {
  if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)}GB';
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)}MB';
  return '${(b / 1024).round()}KB';
}

/// Looks through a title's page (and its embedded or "download" pages, one
/// level deep) for every video file, and works out language and quality from
/// the link text, attributes and file name.
class MediaOptionsFinder {
  MediaOptionsFinder._();

  static const _ua =
      'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36';
  static const _exts = {'mp4', 'mkv', 'webm', 'm4v', 'mov', 'm3u8'};
  static final _hrefMedia =
      RegExp(r'\.(mp4|mkv|webm|m4v|mov|m3u8)(?:$|[?#])', caseSensitive: false);
  static final _mediaInText = RegExp(
      r'''https?://[^"'\s<>\\]+?\.(?:mp4|mkv|webm|m4v|mov|m3u8)(?:\?[^"'\s<>\\]*)?''',
      caseSensitive: false);
  static final _heightRe =
      RegExp(r'(?<![0-9])(2160|1440|1080|720|576|480|360|240)\s*p', caseSensitive: false);
  static final _fourK = RegExp(r'\b(4k|uhd)\b', caseSensitive: false);
  static const _languages = <List<String>>[
    ['dual audio', 'Dual audio'],
    ['hindi', 'Hindi dub'],
    ['english', 'English'],
    ['tamil', 'Tamil dub'],
    ['telugu', 'Telugu dub'],
    ['malayalam', 'Malayalam dub'],
    ['kannada', 'Kannada dub'],
    ['bengali', 'Bengali dub'],
    ['punjabi', 'Punjabi'],
    ['marathi', 'Marathi dub'],
    ['gujarati', 'Gujarati dub'],
    ['urdu', 'Urdu dub'],
    ['spanish', 'Spanish dub'],
    ['french', 'French dub'],
    ['japanese', 'Japanese'],
    ['korean', 'Korean'],
  ];

  static String? _language(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r'[-_.]+'), ' ');
    for (final l in _languages) {
      if (t.contains(l[0])) return l[1];
    }
    return null;
  }

  static ({int height, String label}) _quality(String text) {
    final m = _heightRe.firstMatch(text);
    if (m != null) {
      final h = int.parse(m.group(1)!);
      return (height: h, label: '${h}P');
    }
    if (_fourK.hasMatch(text)) return (height: 2160, label: '2160P');
    return (height: 0, label: 'Standard');
  }

  static Future<List<MediaOption>> find({
    String? pageUrl,
    String? directUrl,
    String languageHint = '',
  }) async {
    final client = http.Client();
    final found = <String, MediaOption>{};
    final visited = <String>{};

    void add(String? raw, Uri base, String text) {
      if (raw == null) return;
      final cleaned = raw.trim().replaceAll('&amp;', '&');
      if (cleaned.isEmpty ||
          cleaned.startsWith('data:') ||
          cleaned.startsWith('javascript:') ||
          cleaned.startsWith('blob:')) {
        return;
      }
      Uri uri;
      try {
        uri = base.resolve(cleaned);
      } catch (_) {
        return;
      }
      if (uri.scheme == 'http') uri = uri.replace(scheme: 'https');
      if (uri.scheme != 'https' || uri.host.isEmpty) return;
      final seg = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      final dot = seg.lastIndexOf('.');
      final ext = dot < 0 ? '' : seg.substring(dot + 1).toLowerCase();
      if (!_exts.contains(ext)) return;
      var fileName = seg;
      try {
        fileName = Uri.decodeComponent(seg);
      } catch (_) {}
      final label = '$text $fileName';
      final q = _quality(label);
      final key = uri.removeFragment().toString();
      final old = found[key];
      if (old != null && (old.height > 0 || q.height == 0)) return;
      found[key] = MediaOption(
        url: key,
        quality: q.label,
        height: q.height,
        language: _language(label) ?? _language(languageHint) ?? 'Original audio',
        ext: ext,
      );
    }

    String context(dom.Element a, String own) {
      if (_heightRe.hasMatch(own) || _fourK.hasMatch(own)) return own;
      final parent = a.parent;
      if (parent == null) return own;
      final siblings = parent
          .querySelectorAll('a[href]')
          .where((e) => _hrefMedia.hasMatch(e.attributes['href'] ?? ''))
          .length;
      if (siblings > 1) return own;
      final text = parent.text.trim();
      return '$own ${text.length > 200 ? text.substring(0, 200) : text}';
    }

    Future<void> scan(Uri page, int depth, Uri? referer) async {
      if (visited.length >= 8 || !visited.add(page.toString())) return;
      final html = await _fetch(client, page, referer);
      if (html == null) return;
      final doc = html_parser.parse(html);

      for (final el in doc.querySelectorAll('video[src], source[src]')) {
        final size = el.attributes['size'];
        final text = [
          el.attributes['label'],
          el.attributes['res'],
          el.attributes['title'],
          el.attributes['data-res'],
          el.attributes['data-quality'],
          if (size != null && RegExp(r'^\d{3,4}$').hasMatch(size)) '${size}p',
        ].whereType<String>().join(' ');
        add(el.attributes['src'], page, text);
      }

      final followPages = <Uri>[];
      for (final a in doc.querySelectorAll('a[href]')) {
        final href = a.attributes['href'] ?? '';
        final own =
            '${a.text} ${a.attributes['title'] ?? ''} ${a.attributes['aria-label'] ?? ''}';
        if (_hrefMedia.hasMatch(href)) {
          add(href, page, context(a, own));
        } else if (depth == 0 &&
            followPages.length < 4 &&
            href.isNotEmpty &&
            RegExp('download', caseSensitive: false).hasMatch('$own $href')) {
          try {
            final u = page.resolve(href);
            if (u.scheme == 'https' && u.host == page.host) followPages.add(u);
          } catch (_) {}
        }
      }

      final cleaned = html.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
      for (final m in _mediaInText.allMatches(cleaned)) {
        final s = m.start - 80 < 0 ? 0 : m.start - 80;
        final e = m.end + 60 > cleaned.length ? cleaned.length : m.end + 60;
        add(m.group(0), page, cleaned.substring(s, e).replaceAll(_mediaInText, ' '));
      }

      if (depth == 0) {
        for (final fr in doc.querySelectorAll('iframe[src], iframe[data-src]').take(3)) {
          final src = (fr.attributes['src'] ?? fr.attributes['data-src'] ?? '').trim();
          if (src.isEmpty || src.startsWith('about:') || src.startsWith('javascript:')) continue;
          try {
            await scan(page.resolve(src), 1, page);
          } catch (_) {}
        }
        for (final u in followPages) {
          await scan(u, 1, page);
        }
      }
    }

    try {
      if (directUrl != null) add(directUrl, Uri.parse(directUrl), '');
      final page = pageUrl == null ? null : Uri.tryParse(pageUrl);
      if (page != null) await scan(page, 0, null);
      final list = found.values.toList()
        ..sort((a, b) {
          final byLang = a.language.compareTo(b.language);
          return byLang != 0 ? byLang : a.height.compareTo(b.height);
        });
      await _fillSizes(client, list, pageUrl);
      return list;
    } catch (_) {
      return found.values.toList();
    } finally {
      client.close();
    }
  }

  /// Downloads at most 600 KB of the page, which is enough to find the links.
  static Future<String?> _fetch(http.Client c, Uri url, Uri? referer) async {
    try {
      final req = http.Request('GET', url)
        ..headers.addAll({
          'User-Agent': _ua,
          'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
          if (referer != null) 'Referer': referer.toString(),
        });
      final res = await c.send(req).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in res.stream.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length >= 600 * 1024) break;
      }
      return String.fromCharCodes(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _fillSizes(http.Client c, List<MediaOption> list, String? referer) async {
    final todo = list.where((o) => !o.isStream).toList();
    for (var i = 0; i < todo.length; i += 6) {
      await Future.wait(todo.skip(i).take(6).map((o) async {
        o.bytes = await _size(c, o.url, referer);
      }));
    }
  }

  /// Reads only the response headers (asks for the first byte) to get the size.
  static Future<int?> _size(http.Client c, String url, String? referer) async {
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers.addAll({
          'User-Agent': _ua,
          'Range': 'bytes=0-0',
          if (referer != null) 'Referer': referer,
        });
      final res = await c.send(req).timeout(const Duration(seconds: 8));
      final sub = res.stream.listen((_) {});
      await sub.cancel();
      final range = res.headers['content-range'];
      if (range != null && range.contains('/')) {
        final total = int.tryParse(range.split('/').last.trim());
        if (total != null && total > 0) return total;
      }
      if (res.statusCode == 200) return res.contentLength;
      return null;
    } catch (_) {
      return null;
    }
  }
}
