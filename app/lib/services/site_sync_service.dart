import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_item.dart';

/// Value of ContentItem.source for titles that come from the user's own website.
const siteSourceName = 'My Website';

class SiteSyncResult {
  final int total, added, pending;
  final String method;
  final String? error;
  const SiteSyncResult({
    required this.total,
    required this.added,
    required this.pending,
    required this.method,
    this.error,
  });
}

class _Found {
  final String url;
  final String title;
  final String? poster, synopsis, video;
  final DateTime? date;
  const _Found(this.url, this.title,
      {this.poster, this.synopsis, this.video, this.date});
}

/// Syncs the catalogue of a website the user owns, entirely on the device.
///
/// The website address is stored only in the app's local preferences. The
/// service auto-detects (in order) a WordPress REST API, an XML sitemap, an
/// RSS/Atom feed, or a plain page of poster cards. Only titles, posters and page
/// links are stored; the playable video is resolved when the user taps Watch or
/// Download.
class SiteSyncService {
  SiteSyncService._();
  static final SiteSyncService instance = SiteSyncService._();

  /// Website address injected at build time from the SITE_URL GitHub secret.
  /// It is never shown in the UI.
  static const _envUrl = String.fromEnvironment('SITE_URL');
  static bool get hasBuiltInUrl => _envUrl.trim().isNotEmpty;

  static const _activeKey = 'moviebox.site_active';
  static const _urlKey = 'moviebox.site_url';
  static const _itemsKey = 'moviebox.site_items';
  static const _skippedKey = 'moviebox.site_skipped';
  static const _lastKey = 'moviebox.site_last_sync';
  static const _pendingKey = 'moviebox.site_pending';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36';

  /// Human readable progress while a sync is running (null when idle).
  final ValueNotifier<String?> progress = ValueNotifier<String?>(null);
  bool _running = false;
  bool get isRunning => _running;

  // ---------------------------------------------------------------- settings
  static Uri? normalize(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !uri.host.contains('.') ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  String? _configured(SharedPreferences prefs) {
    final saved = prefs.getString(_urlKey);
    if (saved != null && saved.trim().isNotEmpty) return saved;
    return _envUrl.trim().isEmpty ? null : _envUrl.trim();
  }

  Future<String?> savedUrl() async =>
      _configured(await SharedPreferences.getInstance());

  Future<void> saveUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_urlKey) != url) {
      await prefs.remove(_itemsKey);
      await prefs.remove(_skippedKey);
      await prefs.remove(_lastKey);
      await prefs.remove(_pendingKey);
    }
    await prefs.setString(_urlKey, url);
  }

  Future<void> remove() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [_urlKey, _itemsKey, _skippedKey, _lastKey, _pendingKey]) {
      await prefs.remove(key);
    }
  }

  Future<DateTime?> lastSync() async {
    final raw = (await SharedPreferences.getInstance()).getString(_lastKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<int> pending() async =>
      (await SharedPreferences.getInstance()).getInt(_pendingKey) ?? 0;

  Future<List<ContentItem>> cachedItems() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _decode(prefs.getString(_itemsKey)).values.toList()
      ..sort((a, b) => ((b['sort'] as num?) ?? 0).compareTo((a['sort'] as num?) ?? 0));
    return list.map((m) => ContentItem.fromMap(m)).toList(growable: false);
  }

  /// Auto sync when a website is configured and it has not synced for 3 hours,
  /// or an earlier sync stopped before reading every page.
  Future<bool> shouldAutoSync() async {
    final prefs = await SharedPreferences.getInstance();
    if (_configured(prefs) == null) return false;
    if ((prefs.getInt(_pendingKey) ?? 0) > 0) return true;
    final last = DateTime.tryParse(prefs.getString(_lastKey) ?? '');
    return last == null || DateTime.now().difference(last) > const Duration(hours: 3);
  }

  // -------------------------------------------------------------------- sync
  Future<SiteSyncResult> sync() async {
    if (_running) {
      return const SiteSyncResult(total: 0, added: 0, pending: 0, method: 'busy');
    }
    _running = true;
    final client = http.Client();
    try {
      final prefs = await SharedPreferences.getInstance();
      final configured = _configured(prefs);
      final base = normalize(configured ?? '');
      if (base == null) {
        throw FormatException(configured == null
            ? 'No website is set up yet.'
            : 'The website address must be a valid https:// link.');
      }
      // A different website than last time: start from a clean cache.
      if (prefs.getString(_activeKey) != base.toString()) {
        for (final key in [_itemsKey, _skippedKey, _lastKey, _pendingKey]) {
          await prefs.remove(key);
        }
        await prefs.setString(_activeKey, base.toString());
      }
      final items = _decode(prefs.getString(_itemsKey));
      final skipped = <String>{...(prefs.getStringList(_skippedKey) ?? const <String>[])};
      final label = _hostLabel(base);
      final now = DateTime.now();
      var added = 0;
      var pending = 0;
      var method = '';

      bool add(_Found f, int index) {
        final old = items[f.url];
        if (old != null) {
          if (old['poster_url'] == null && f.poster != null) old['poster_url'] = f.poster;
          if (old['video_url'] == null && f.video != null) old['video_url'] = f.video;
          return false;
        }
        final stamp =
            (f.date ?? now.subtract(Duration(seconds: index))).millisecondsSinceEpoch;
        items[f.url] = <String, dynamic>{
          'id': 'site-${_fnv(f.url)}',
          'title': f.title,
          'content_type': _guessType(f.title),
          'synopsis': f.synopsis,
          'poster_url': f.poster,
          'video_url': f.video,
          'language': RegExp('hindi', caseSensitive: false).hasMatch(f.title) ? 'Hindi' : null,
          'source': siteSourceName,
          'source_url': f.url,
          'release_year': _guessYear(f.title),
          'sort': stamp,
        };
        return true;
      }

      progress.value = 'Checking website...';

      // 1) WordPress REST API: complete history, posters and dates in one go.
      var found = await _wordpress(client, base) ?? <_Found>[];
      if (found.isNotEmpty) method = 'WordPress';

      // 2) XML sitemap: every page, read incrementally (new pages only).
      if (method.isEmpty) {
        final urls = await _sitemapUrls(client, base);
        if (urls.isNotEmpty) {
          method = 'Sitemap';
          final fresh =
              urls.where((u) => !items.containsKey(u) && !skipped.contains(u)).toList();
          final deadline = DateTime.now().add(const Duration(seconds: 150));
          var done = 0;
          var chunks = 0;
          for (var i = 0; i < fresh.length; i += 8) {
            if (DateTime.now().isAfter(deadline)) break;
            final chunk = fresh.skip(i).take(8).toList();
            final results = await Future.wait(chunk.map((u) => _readPage(client, u, label)));
            for (var j = 0; j < chunk.length; j++) {
              final r = results[j];
              if (r == null) {
                skipped.add(chunk[j]);
              } else if (add(r, done + j)) {
                added++;
              }
            }
            done += chunk.length;
            chunks++;
            progress.value = 'Reading titles... $done / ${fresh.length}';
            if (chunks % 5 == 0) await _persist(prefs, items, skipped);
          }
          pending = fresh.length - done;
        }
      }

      // 3) RSS / Atom feed: latest titles.
      if (method.isEmpty) {
        found = await _rss(client, base) ?? <_Found>[];
        if (found.isNotEmpty) method = 'Feed';
      }

      // 4) Poster cards on the page itself.
      if (method.isEmpty) {
        found = await _cards(client, base) ?? <_Found>[];
        if (found.isNotEmpty) method = 'Page';
      }

      for (var i = 0; i < found.length; i++) {
        if (add(found[i], i)) added++;
      }

      if (method.isEmpty && items.isEmpty) {
        throw const FormatException(
            'No titles could be found automatically. The site may need a login or use a layout the app cannot read yet.');
      }

      await _persist(prefs, items, skipped);
      await prefs.setString(_lastKey, DateTime.now().toIso8601String());
      await prefs.setInt(_pendingKey, pending);
      return SiteSyncResult(
          total: items.length,
          added: added,
          pending: pending,
          method: method.isEmpty ? 'Saved list' : method);
    } catch (e) {
      return SiteSyncResult(
          total: 0, added: 0, pending: 0, method: '', error: _friendly(e));
    } finally {
      client.close();
      _running = false;
      progress.value = null;
    }
  }

  // ------------------------------------------------------------- strategies
  Future<List<_Found>?> _wordpress(http.Client c, Uri base) async {
    final origin = _origin(base);
    final probe = await _get(
        c, origin.replace(path: '/wp-json/wp/v2/posts', queryParameters: {'per_page': '1'}),
        seconds: 12);
    if (probe == null ||
        probe.statusCode != 200 ||
        !probe.body.trimLeft().startsWith('[')) {
      return null;
    }
    final bases = <String>['posts'];
    final typesResp =
        await _get(c, origin.replace(path: '/wp-json/wp/v2/types'), seconds: 12);
    if (typesResp != null && typesResp.statusCode == 200) {
      try {
        final types = jsonDecode(typesResp.body);
        if (types is Map) {
          const ignore = {
            'pages', 'media', 'blocks', 'templates', 'template-parts',
            'navigation', 'menu-items', 'font-families', 'global-styles'
          };
          for (final entry in types.entries) {
            final rb = _map(entry.value)?['rest_base']?.toString();
            if (rb == null || rb.isEmpty || bases.contains(rb) || ignore.contains(rb)) {
              continue;
            }
            bases.add(rb);
          }
        }
      } catch (_) {}
    }

    final out = <_Found>[];
    for (final rb in bases) {
      for (var page = 1; page <= 40; page++) {
        progress.value = 'Reading $rb... page $page';
        final r = await _get(
            c,
            origin.replace(path: '/wp-json/wp/v2/$rb', queryParameters: {
              'per_page': '100',
              'page': '$page',
              '_embed': 'wp:featuredmedia',
            }),
            seconds: 30);
        if (r == null || r.statusCode != 200) break;
        List<dynamic> list;
        try {
          final decoded = jsonDecode(r.body);
          if (decoded is! List) break;
          list = decoded;
        } catch (_) {
          break;
        }
        if (list.isEmpty) break;
        for (final raw in list) {
          final m = _map(raw);
          if (m == null) continue;
          final f = _fromWp(m);
          if (f != null) out.add(f);
        }
        if (list.length < 100) break;
      }
    }
    return out;
  }

  _Found? _fromWp(Map<String, dynamic> m) {
    final link = _https(m['link']?.toString());
    final title = _text(_map(m['title'])?['rendered']);
    if (link == null || title.isEmpty) return null;
    final content = _map(m['content'])?['rendered']?.toString() ?? '';
    final excerpt = _text(_map(m['excerpt'])?['rendered']);

    String? poster;
    final embedded = _map(m['_embedded']);
    final media = embedded == null ? null : embedded['wp:featuredmedia'];
    if (media is List && media.isNotEmpty) {
      poster = _map(media.first)?['source_url']?.toString();
    }
    poster ??= m['jetpack_featured_media_url']?.toString();
    if (poster == null || poster.isEmpty) {
      poster = RegExp(r'''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false)
          .firstMatch(content)
          ?.group(1);
    }

    final video = RegExp(
            r'''https?://[^"'\s<>\\]+\.(?:mp4|m3u8|webm|m4v)(?:\?[^"'\s<>\\]*)?''',
            caseSensitive: false)
        .firstMatch(content)
        ?.group(0)
        ?.replaceAll('&#038;', '&')
        .replaceAll('&amp;', '&');

    return _Found(link, title,
        poster: _https(poster),
        synopsis: excerpt.isEmpty ? null : _shorten(excerpt),
        video: _https(video),
        date: DateTime.tryParse(
            m['date_gmt']?.toString() ?? m['date']?.toString() ?? ''));
  }

  Future<List<String>> _sitemapUrls(http.Client c, Uri base) async {
    final origin = _origin(base);
    final queue = <Uri>[];
    final robots = await _get(c, origin.resolve('/robots.txt'), seconds: 8);
    if (robots != null && robots.statusCode == 200) {
      for (final line in const LineSplitter().convert(robots.body)) {
        if (line.toLowerCase().startsWith('sitemap:')) {
          final u = Uri.tryParse(line.substring(8).trim());
          if (u != null && u.hasScheme) queue.add(u);
        }
      }
    }
    for (final p in const ['/sitemap.xml', '/sitemap_index.xml', '/wp-sitemap.xml']) {
      queue.add(origin.resolve(p));
    }

    final locRe = RegExp(
        r'<loc>\s*(?:<!\[CDATA\[)?\s*([^<\]\s]+)\s*(?:\]\]>)?\s*</loc>',
        caseSensitive: false);
    final seen = <String>{};
    final urls = <String>{};
    var fetched = 0;
    while (queue.isNotEmpty && fetched < 40) {
      final u = queue.removeAt(0);
      if (!seen.add(u.toString()) || u.host != origin.host) continue;
      progress.value = 'Reading sitemap...';
      final r = await _get(c, u, seconds: 25);
      fetched++;
      if (r == null || r.statusCode != 200) continue;
      final body = r.body;
      final isIndex = body.contains('<sitemapindex');
      for (final m in locRe.allMatches(body)) {
        final raw = m.group(1)!.replaceAll('&amp;', '&');
        final lu = Uri.tryParse(raw);
        if (lu == null) continue;
        if (isIndex || raw.toLowerCase().endsWith('.xml')) {
          queue.add(lu);
        } else {
          final https = _https(raw);
          final parsed = https == null ? null : Uri.tryParse(https);
          if (parsed != null && _looksLikeContent(parsed, origin)) urls.add(parsed.toString());
        }
      }
    }
    return urls.toList();
  }

  Future<_Found?> _readPage(http.Client c, String url, String label) async {
    try {
      final r = await _get(c, Uri.parse(url), seconds: 15);
      if (r == null || r.statusCode != 200) return null;
      if (!(r.headers['content-type']?.toLowerCase().contains('html') ?? false)) return null;
      if (r.bodyBytes.length > 3 * 1024 * 1024) return null;
      final doc = html_parser.parse(utf8.decode(r.bodyBytes, allowMalformed: true));
      String? meta(String key) =>
          doc.querySelector('meta[property="$key"]')?.attributes['content'] ??
          doc.querySelector('meta[name="$key"]')?.attributes['content'];

      var title = _text(meta('og:title') ?? doc.querySelector('title')?.text ?? '');
      title = _cleanTitle(title, label);
      if (title.isEmpty) return null;
      final pageUri = Uri.parse(url);
      final posterRaw = meta('og:image') ?? meta('twitter:image');
      final poster = posterRaw == null ? null : _https(pageUri.resolve(posterRaw).toString());
      if ((meta('og:type') ?? '').toLowerCase() == 'website' && poster == null) {
        return null;
      }
      final desc = _text(meta('og:description') ?? meta('description') ?? '');
      final videoRaw = meta('og:video:secure_url') ?? meta('og:video') ?? meta('og:video:url');
      final video = videoRaw == null ? null : _https(pageUri.resolve(videoRaw).toString());
      return _Found(url, title,
          poster: poster,
          synopsis: desc.isEmpty ? null : _shorten(desc),
          video: video,
          date: DateTime.tryParse(meta('article:published_time') ?? ''));
    } catch (_) {
      return null;
    }
  }

  Future<List<_Found>?> _rss(http.Client c, Uri base) async {
    final origin = _origin(base);
    final blockRe = RegExp(r'<(item|entry)[\s>].*?</\1>', dotAll: true, caseSensitive: false);
    for (final p in const ['/feed/', '/feed', '/rss.xml', '/feed.xml', '/atom.xml', '/rss']) {
      progress.value = 'Checking feed $p...';
      final r = await _get(c, origin.resolve(p), seconds: 15);
      if (r == null || r.statusCode != 200) continue;
      final blocks = blockRe.allMatches(r.body).map((m) => m.group(0)!).toList();
      if (blocks.isEmpty) continue;
      final out = <_Found>[];
      for (final b in blocks) {
        final title = _text(_tag(b, 'title'));
        var link = _tag(b, 'link');
        if (link == null || link.isEmpty) {
          link = RegExp(r'''<link[^>]*href=["']([^"']+)["']''', caseSensitive: false)
              .firstMatch(b)
              ?.group(1);
        }
        final url = _https(link);
        if (title.isEmpty || url == null) continue;
        final decoded = b.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"');
        final poster = RegExp(r'''<media:(?:thumbnail|content)[^>]+url=["']([^"']+)["']''',
                    caseSensitive: false)
                .firstMatch(decoded)
                ?.group(1) ??
            RegExp(r'''<enclosure[^>]+url=["']([^"']+\.(?:jpe?g|png|webp))["']''',
                    caseSensitive: false)
                .firstMatch(decoded)
                ?.group(1) ??
            RegExp(r'''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false)
                .firstMatch(decoded)
                ?.group(1);
        final desc = _text(_tag(b, 'description') ?? _tag(b, 'summary') ?? '');
        out.add(_Found(url, title,
            poster: _https(poster), synopsis: desc.isEmpty ? null : _shorten(desc)));
      }
      if (out.isNotEmpty) return out;
    }
    return null;
  }

  Future<List<_Found>?> _cards(http.Client c, Uri base) async {
    final origin = _origin(base);
    final out = <_Found>[];
    final seen = <String>{};
    Uri? next = base;
    for (var page = 0; page < 10 && next != null; page++) {
      final current = next;
      progress.value = 'Reading page ${page + 1}...';
      final r = await _get(c, current, seconds: 20);
      if (r == null || r.statusCode != 200) break;
      final doc = html_parser.parse(utf8.decode(r.bodyBytes, allowMalformed: true));
      for (final a in doc.querySelectorAll('a[href]')) {
        final img = a.querySelector('img');
        final href = a.attributes['href'];
        if (img == null || href == null) continue;
        final target = current.resolve(href).removeFragment();
        if (target.scheme != 'https' || !_looksLikeContent(target, origin)) continue;
        final url = target.toString();
        if (!seen.add(url)) continue;
        final posterRaw = img.attributes['data-src'] ??
            img.attributes['data-lazy-src'] ??
            img.attributes['src'];
        final poster =
            posterRaw == null ? null : _https(current.resolve(posterRaw).toString());
        final title = _text(a.attributes['title'] ?? img.attributes['alt'] ?? a.text);
        if (title.length < 2) continue;
        out.add(_Found(url, title, poster: poster));
      }
      final nextHref =
          doc.querySelector('a[rel="next"], link[rel="next"]')?.attributes['href'];
      final candidate = nextHref == null ? null : current.resolve(nextHref);
      next = (candidate == null || candidate.toString() == current.toString())
          ? null
          : candidate;
    }
    return out.isEmpty ? null : out;
  }

  // ----------------------------------------------------------------- helpers
  Future<http.Response?> _get(http.Client c, Uri u, {int seconds = 15}) async {
    try {
      return await c
          .get(u, headers: const {'User-Agent': _ua, 'Accept': '*/*'})
          .timeout(Duration(seconds: seconds));
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(SharedPreferences prefs,
      Map<String, Map<String, dynamic>> items, Set<String> skipped) async {
    final list = items.values.toList()
      ..sort((a, b) => ((b['sort'] as num?) ?? 0).compareTo((a['sort'] as num?) ?? 0));
    await prefs.setString(_itemsKey, jsonEncode(list));
    await prefs.setStringList(_skippedKey, skipped.take(5000).toList());
  }

  Map<String, Map<String, dynamic>> _decode(String? raw) {
    final out = <String, Map<String, dynamic>>{};
    if (raw == null) return out;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        for (final e in list) {
          final m = _map(e);
          final url = m?['source_url']?.toString();
          if (m != null && url != null) out[url] = m;
        }
      }
    } catch (_) {}
    return out;
  }

  Uri _origin(Uri b) =>
      Uri(scheme: b.scheme, host: b.host, port: b.hasPort ? b.port : null);

  String _hostLabel(Uri b) {
    final host = b.host.startsWith('www.') ? b.host.substring(4) : b.host;
    return host.split('.').first.toLowerCase();
  }

  Map<String, dynamic>? _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  String? _https(String? url) {
    if (url == null) return null;
    final t = url.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('http://')) return 'https://${t.substring(7)}';
    return t.startsWith('https://') ? t : null;
  }

  String _text(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.isEmpty) return '';
    final t = html_parser.parseFragment(s).text ?? '';
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _shorten(String s) => s.length <= 400 ? s : '${s.substring(0, 397)}...';

  String? _tag(String block, String name) {
    final m = RegExp(
            '<$name(?:\\s[^>]*)?>\\s*(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?\\s*</$name>',
            dotAll: true,
            caseSensitive: false)
        .firstMatch(block);
    return m?.group(1)?.trim();
  }

  /// Removes a trailing " | Site Name" style suffix, but only when it matches
  /// the website's own name, so real titles containing dashes stay intact.
  String _cleanTitle(String title, String label) {
    var s = title.trim();
    if (label.isEmpty) return s;
    for (final sep in const [' | ', ' – ', ' — ', ' - ']) {
      final i = s.lastIndexOf(sep);
      if (i > 2) {
        final suffix = s.substring(i + sep.length).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (suffix.contains(label)) {
          s = s.substring(0, i).trim();
          break;
        }
      }
    }
    return s;
  }

  bool _looksLikeContent(Uri u, Uri origin) {
    if (u.host != origin.host) return false;
    final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return false;
    if (RegExp(r'\.(jpe?g|png|gif|webp|svg|pdf|css|js|xml|zip|txt)$', caseSensitive: false)
        .hasMatch(segs.last)) {
      return false;
    }
    const skip = {
      'category', 'categories', 'tag', 'tags', 'author', 'page', 'feed',
      'wp-content', 'wp-json', 'wp-admin', 'search', 'cart', 'checkout',
      'my-account', 'login', 'register', 'contact', 'contact-us', 'about',
      'about-us', 'privacy-policy', 'terms', 'dmca', 'disclaimer'
    };
    return !segs.any((s) => skip.contains(s.toLowerCase()));
  }

  String _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  String _guessType(String title) => RegExp(
              r'season|\bs\d{1,2}\s?e\d{1,2}\b|episode|web\s?series|\bseries\b',
              caseSensitive: false)
          .hasMatch(title)
      ? 'series'
      : 'movie';

  int? _guessYear(String title) {
    final m = RegExp(r'(?:^|[^\d])((?:19|20)\d{2})(?:[^\d]|$)').firstMatch(title);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  String _friendly(Object e) {
    if (e is FormatException) return e.message;
    if (e is TimeoutException) return 'The website took too long to respond.';
    return 'Could not reach the website. Check the address and your internet.';
  }
}
