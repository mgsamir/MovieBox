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

class _SmEntry {
  final String url;
  final List<String> images;
  final DateTime? lastmod;
  const _SmEntry(this.url, {this.images = const [], this.lastmod});
}

class _Found {
  final String url;
  final String title;
  final String? poster, synopsis, video;
  final DateTime? date;
  final List<String> images;
  const _Found(this.url, this.title,
      {this.poster, this.synopsis, this.video, this.date, this.images = const []});
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
  static const _schemaKey = 'moviebox.site_schema';
  static const _schema = 2;
  static const _urlKey = 'moviebox.site_url';
  static const _itemsKey = 'moviebox.site_items';
  static const _skippedKey = 'moviebox.site_skipped';
  static const _lastKey = 'moviebox.site_last_sync';
  static const _pendingKey = 'moviebox.site_pending';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36';

  static const _logKey = 'moviebox.site_log';

  /// Increases whenever new titles were saved, so screens can refresh.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final List<String> _logLines = [];
  String? _firstPageProblem;
  void _log(String line) {
    if (_logLines.length < 80) _logLines.add(line);
  }

  Future<List<String>> lastLog() async =>
      (await SharedPreferences.getInstance()).getStringList(_logKey) ?? const <String>[];

  Future<int> cachedCount() async => (await cachedItems()).length;

  /// Forget everything that was saved from the website (used by Reset).
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [_itemsKey, _skippedKey, _lastKey, _pendingKey, _activeKey, _logKey]) {
      await prefs.remove(key);
    }
    revision.value++;
  }

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
    _dropSharedPosters(list);
    return list.map((m) => ContentItem.fromMap(m)).toList(growable: false);
  }

  /// An image repeated across many titles (logo, badge, placeholder) is not a
  /// real poster, so each title uses its first image that is not shared.
  void _dropSharedPosters(List<Map<String, dynamic>> list) {
    if (list.length < 6) return;
    List<String> candidates(Map<String, dynamic> m) => <String>{
          if (m['poster_url'] is String) m['poster_url'] as String,
          ...((m['imgs'] as List?)?.whereType<String>() ?? const <String>[]),
        }.toList();
    final counts = <String, int>{};
    for (final m in list) {
      for (final u in candidates(m)) {
        counts[u] = (counts[u] ?? 0) + 1;
      }
    }
    for (final m in list) {
      String? chosen;
      for (final u in candidates(m)) {
        if ((counts[u] ?? 0) <= 2) {
          chosen = u;
          break;
        }
      }
      m['poster_url'] = chosen;
    }
  }

  /// Auto sync when a website is configured and it has not synced for 24 hours.
  Future<bool> shouldAutoSync() async {
    final prefs = await SharedPreferences.getInstance();
    if (_configured(prefs) == null) return false;
    final last = DateTime.tryParse(prefs.getString(_lastKey) ?? '');
    return last == null || DateTime.now().difference(last) > const Duration(hours: 24);
  }

  // -------------------------------------------------------------------- sync
  Future<SiteSyncResult> sync() async {
    if (_running) {
      return const SiteSyncResult(total: 0, added: 0, pending: 0, method: 'busy');
    }
    _running = true;
    _logLines.clear();
    _firstPageProblem = null;
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
      if (prefs.getString(_activeKey) != base.toString() ||
          prefs.getInt(_schemaKey) != _schema) {
        await prefs.setInt(_schemaKey, _schema);
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

      // 2) XML sitemap: list every page at once, then read details newest-first.
      if (method.isEmpty) {
        final entries = await _sitemapEntries(client, base);
        if (entries.isNotEmpty) {
          method = 'Sitemap';
          for (var i = 0; i < entries.length; i++) {
            final e = entries[i];
            if (items.containsKey(e.url) || skipped.contains(e.url)) continue;
            final title = _titleFromUrl(e.url);
            if (title.isEmpty) continue;
            items[e.url] = <String, dynamic>{
              'id': 'site-${_fnv(e.url)}',
              'title': title,
              'content_type': _guessType(title),
              'poster_url': e.images.isEmpty ? null : e.images.first,
              'imgs': e.images,
              'language': RegExp('hindi', caseSensitive: false).hasMatch(title) ? 'Hindi' : null,
              'source': siteSourceName,
              'source_url': e.url,
              'release_year': _guessYear(title),
              'sort': (e.lastmod ?? now.subtract(Duration(seconds: i))).millisecondsSinceEpoch,
            };
            added++;
          }
          // Titles are visible immediately; details are filled in below.
          await _persist(prefs, items, skipped);

          final fresh = entries.where((e) {
            final it = items[e.url];
            return it != null && it['e'] != 1 && ((it['t'] as num?) ?? 0) < 3;
          }).toList()
            ..sort((a, b) => ((items[b.url]!['sort'] as num?) ?? 0)
                .compareTo((items[a.url]!['sort'] as num?) ?? 0));
          final deadline = DateTime.now().add(const Duration(seconds: 300));
          var done = 0;
          var chunks = 0;
          var ok = 0;
          for (var i = 0; i < fresh.length; i += 12) {
            if (DateTime.now().isAfter(deadline)) break;
            final chunk = fresh.skip(i).take(12).toList();
            final results =
                await Future.wait(chunk.map((e) => _readPage(client, e.url, label)));
            for (var j = 0; j < chunk.length; j++) {
              final it = items[chunk[j].url]!;
              final r = results[j];
              if (r == null) {
                it['t'] = ((it['t'] as num?) ?? 0).toInt() + 1;
              } else {
                _enrich(it, r);
                ok++;
              }
            }
            done += chunk.length;
            chunks++;
            progress.value = 'Reading titles... $done / ${fresh.length}';
            if (chunks % 2 == 0) await _persist(prefs, items, skipped);
          }
          pending = fresh.length - done;
          _log('Page details read: $ok of $done');
          if (_firstPageProblem != null) _log('First page problem: $_firstPageProblem');
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
      final text = _friendly(e);
      _log('Result: $text');
      return SiteSyncResult(
          total: 0, added: 0, pending: 0, method: '', error: text);
    } finally {
      client.close();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_logKey, List<String>.from(_logLines));
      } catch (_) {}
      _running = false;
      progress.value = null;
    }
  }

  // ------------------------------------------------------------- strategies
  Future<List<_Found>?> _wordpress(http.Client c, Uri base) async {
    final origin = _origin(base);
    final probe = await _get(
        c, origin.replace(path: '/wp-json/wp/v2/posts', queryParameters: {'per_page': '1'}),
        seconds: 12, tag: 'WordPress API');
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

  Future<List<_SmEntry>> _sitemapEntries(http.Client c, Uri base) async {
    final origin = _origin(base);
    final queue = <Uri>[];
    final robots = await _get(c, origin.resolve('/robots.txt'), seconds: 8, tag: 'robots.txt');
    if (robots != null && robots.statusCode == 200) {
      for (final line in const LineSplitter().convert(robots.body)) {
        if (line.toLowerCase().startsWith('sitemap:')) {
          final u = Uri.tryParse(line.substring(8).trim());
          if (u != null && u.hasScheme) queue.add(u);
        }
      }
      _log('robots.txt lists ${queue.length} sitemap(s)');
    }
    for (final p in const [
      '/sitemap.xml', '/sitemap_index.xml', '/sitemap-index.xml',
      '/wp-sitemap.xml', '/post-sitemap.xml'
    ]) {
      queue.add(origin.resolve(p));
    }

    final locRe = RegExp(
        r'<loc>\s*(?:<!\[CDATA\[)?\s*([^<\]\s]+)\s*(?:\]\]>)?\s*</loc>',
        caseSensitive: false);
    final urlRe = RegExp(r'<url(?:\s[^>]*)?>(.*?)</url>', dotAll: true, caseSensitive: false);
    final imgRe = RegExp(r'<image:loc>\s*(?:<!\[CDATA\[)?\s*([^<\]\s]+)', caseSensitive: false);
    final modRe = RegExp(r'<lastmod>\s*([^<\s]+)\s*</lastmod>', caseSensitive: false);
    final skipName = RegExp(
        r'(^|[-_/.])(page|pages|category|categories|post_tag|tag|tags|author|authors|attachment|taxonomy|product_cat|user|users)([-_.]|$)',
        caseSensitive: false);

    final seen = <String>{};
    final out = <String, _SmEntry>{};
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    var fetched = 0;
    while (queue.isNotEmpty && fetched < 60 && DateTime.now().isBefore(deadline)) {
      final batch = <Uri>[];
      while (queue.isNotEmpty && batch.length < 4) {
        final u = queue.removeAt(0);
        if (u.host != origin.host || !seen.add(u.toString())) continue;
        batch.add(u);
      }
      if (batch.isEmpty) continue;
      progress.value = 'Reading sitemap...';
      final results = await Future.wait(batch.map((u) => _get(c, u, seconds: 20)));
      for (var i = 0; i < batch.length; i++) {
        final r = results[i];
        fetched++;
        if (r == null) {
          _log('Sitemap file $fetched: no response');
          continue;
        }
        if (r.statusCode != 200) {
          _log('Sitemap file $fetched: HTTP ${r.statusCode}');
          continue;
        }
        final body = r.body;
        if (body.contains('<sitemapindex')) {
          var n = 0;
          for (final m in locRe.allMatches(body)) {
            final lu = Uri.tryParse(m.group(1)!.replaceAll('&amp;', '&'));
            if (lu == null) continue;
            final name = lu.pathSegments.isEmpty ? '' : lu.pathSegments.last;
            if (skipName.hasMatch(name)) continue;
            queue.add(lu);
            n++;
          }
          _log('Sitemap index $fetched: $n content sitemap(s)');
          continue;
        }
        var pages = 0;
        for (final m in urlRe.allMatches(body)) {
          final block = m.group(1)!;
          final loc = locRe.firstMatch(block)?.group(1);
          if (loc == null) continue;
          final https = _https(loc.replaceAll('&amp;', '&'));
          final parsed = https == null ? null : Uri.tryParse(https);
          if (parsed == null || !_looksLikeContent(parsed, origin)) continue;
          final images = <String>[];
          for (final im in imgRe.allMatches(block)) {
            final u = _https(im.group(1)?.replaceAll('&amp;', '&'));
            if (u != null && !images.contains(u) && images.length < 4) images.add(u);
          }
          out[parsed.toString()] = _SmEntry(parsed.toString(),
              images: images,
              lastmod: DateTime.tryParse(modRe.firstMatch(block)?.group(1) ?? ''));
          pages++;
        }
        _log('Sitemap file $fetched: $pages page(s)');
      }
    }
    return out.values.toList();
  }

  String _titleFromUrl(String url) {
    try {
      final segs = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty) return '';
      var slug = Uri.decodeComponent(segs.last)
          .replaceAll(RegExp(r'\.(html?|php|aspx?)$', caseSensitive: false), '')
          .replaceAll(RegExp(r'[-_+]+'), ' ')
          .trim();
      if (slug.length < 2) return '';
      return slug
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + w.substring(1))
          .join(' ');
    } catch (_) {
      return '';
    }
  }

  void _enrich(Map<String, dynamic> it, _Found f) {
    it['title'] = f.title;
    it['content_type'] = _guessType(f.title);
    it['release_year'] = _guessYear(f.title);
    if (RegExp('hindi', caseSensitive: false).hasMatch(f.title)) it['language'] = 'Hindi';
    if (f.poster != null) it['poster_url'] = f.poster;
    if (f.images.isNotEmpty) it['imgs'] = f.images;
    if (f.synopsis != null) it['synopsis'] = f.synopsis;
    if (f.video != null) it['video_url'] = f.video;
    if (f.date != null) it['sort'] = f.date!.millisecondsSinceEpoch;
    it['e'] = 1;
  }

  Future<_Found?> _readPage(http.Client c, String url, String label) async {
    try {
      // Only the first part of the page is needed (title, poster, description),
      // so stop downloading after 150 KB to make this much faster.
      final req = http.Request('GET', Uri.parse(url))
        ..headers.addAll(const {'User-Agent': _ua, 'Accept': '*/*'});
      http.StreamedResponse r;
      try {
        r = await c.send(req).timeout(const Duration(seconds: 15));
      } catch (_) {
        _firstPageProblem ??= 'no response';
        return null;
      }
      if (r.statusCode != 200) {
        _firstPageProblem ??= 'HTTP ${r.statusCode}';
        return null;
      }
      if (!(r.headers['content-type']?.toLowerCase().contains('html') ?? false)) return null;
      final bytes = <int>[];
      await for (final chunk in r.stream.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length >= 150 * 1024) break;
      }
      final doc = html_parser.parse(utf8.decode(bytes, allowMalformed: true));
      String? meta(String key) =>
          doc.querySelector('meta[property="$key"]')?.attributes['content'] ??
          doc.querySelector('meta[name="$key"]')?.attributes['content'];

      var title = _text(meta('og:title') ?? doc.querySelector('title')?.text ?? '');
      title = _cleanTitle(title, label);
      if (title.isEmpty) return null;
      final pageUri = Uri.parse(url);
      final images = <String>[];
      void addImage(String? raw) {
        if (raw == null || images.length >= 5) return;
        final trimmed = raw.trim();
        if (trimmed.isEmpty || trimmed.startsWith('data:')) return;
        final u = _https(pageUri.resolve(trimmed).toString());
        if (u == null) return;
        final bare = u.toLowerCase().split('?').first;
        if (bare.endsWith('.svg') || bare.endsWith('.ico')) return;
        if (!images.contains(u)) images.add(u);
      }
      addImage(meta('og:image'));
      addImage(meta('twitter:image'));
      addImage(doc.querySelector('link[rel="image_src"]')?.attributes['href']);
      for (final img in doc.querySelectorAll('img')) {
        if (images.length >= 5) break;
        addImage(img.attributes['data-src'] ??
            img.attributes['data-lazy-src'] ??
            img.attributes['src']);
      }
      final poster = images.isEmpty ? null : images.first;
      if ((meta('og:type') ?? '').toLowerCase() == 'website' && poster == null) {
        return null;
      }
      final desc = _text(meta('og:description') ?? meta('description') ?? '');
      final videoRaw = meta('og:video:secure_url') ?? meta('og:video') ?? meta('og:video:url');
      final video = videoRaw == null ? null : _https(pageUri.resolve(videoRaw).toString());
      return _Found(url, title,
          poster: poster,
          images: images,
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
      final r = await _get(c, origin.resolve(p), seconds: 15, tag: 'Feed $p');
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
      final r = await _get(c, current, seconds: 20, tag: 'Page ${page + 1}');
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
  Future<http.Response?> _get(http.Client c, Uri u, {int seconds = 15, String? tag}) async {
    try {
      final r = await c
          .get(u, headers: const {'User-Agent': _ua, 'Accept': '*/*'})
          .timeout(Duration(seconds: seconds));
      if (tag != null) _log('$tag: HTTP ${r.statusCode}');
      return r;
    } catch (e) {
      if (tag != null) _log('$tag: ${e is TimeoutException ? 'timed out' : 'connection failed'}');
      return null;
    }
  }

  Future<void> _persist(SharedPreferences prefs,
      Map<String, Map<String, dynamic>> items, Set<String> skipped) async {
    final list = items.values.toList()
      ..sort((a, b) => ((b['sort'] as num?) ?? 0).compareTo((a['sort'] as num?) ?? 0));
    await prefs.setString(_itemsKey, jsonEncode(list.take(3000).toList()));
    await prefs.setStringList(_skippedKey, skipped.take(5000).toList());
    revision.value++;
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
