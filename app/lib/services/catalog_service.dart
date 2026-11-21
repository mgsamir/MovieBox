import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/content_item.dart';
import '../models/season_episode.dart';

class CatalogService {
  final SupabaseClient? _db;

  CatalogService({SupabaseClient? client})
      : _db = client ??
            (AppConfig.hasSupabaseConfig ? Supabase.instance.client : null);

  Future<List<ContentItem>> loadAll({
    String query = '',
    String? type,
    int limit = 150,
  }) async {
    if (_db != null) {
      try {
        var request = _db!
            .from('content')
            .select(
              'id,title,content_type,synopsis,poster_url,backdrop_url,'
              'release_year,rating,language,source,source_url,video_url',
            );
        if (type != null && type != 'all') {
          request = request.eq('content_type', type);
        }
        if (query.trim().isNotEmpty) {
          request = request.ilike('title', '%${query.trim()}%');
        }
        final rows = await request.order('title').limit(limit);
        final items = _deduplicate(rows);
        if (items.isNotEmpty) return items;
      } catch (_) {
        // A missing table, empty database, or offline backend must not blank Home.
      }
    }

    final fallback = await _loadPublicMetadata();
    final filtered = fallback.where((item) {
      final typeMatches = type == null ||
          type == 'all' ||
          item.type.toLowerCase() == type.toLowerCase();
      final queryMatches = query.trim().isEmpty ||
          item.title.toLowerCase().contains(query.trim().toLowerCase());
      return typeMatches && queryMatches;
    }).toList();
    filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return filtered.take(limit).toList(growable: false);
  }

  List<ContentItem> _deduplicate(Iterable<dynamic> rows) {
    final unique = <String, ContentItem>{};
    for (final row in rows) {
      final item = ContentItem.fromMap(Map<String, dynamic>.from(row));
      if (item.id.isNotEmpty && item.title.trim().isNotEmpty) {
        unique.putIfAbsent(item.title.trim().toLowerCase(), () => item);
      }
    }
    return unique.values.toList(growable: false);
  }

  Future<List<ContentItem>> _loadPublicMetadata() async {
    final items = <ContentItem>[];
    final client = http.Client();
    try {
      // Jikan supplies public anime metadata and poster artwork, not Hindi audio.
      try {
        final response = await client
            .get(Uri.parse('https://api.jikan.moe/v4/top/anime?limit=25'))
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          for (final raw in (data['data'] as List? ?? const [])) {
            final a = Map<String, dynamic>.from(raw as Map);
            final images = Map<String, dynamic>.from(a['images'] as Map? ?? {});
            final jpg = Map<String, dynamic>.from(images['jpg'] as Map? ?? {});
            items.add(ContentItem.fromMap({
              'id': 'jikan-${a['mal_id']}',
              'title': a['title'],
              'content_type': 'anime',
              'synopsis': a['synopsis'],
              'poster_url': jpg['large_image_url'] ?? jpg['image_url'],
              'release_year': a['year'],
              'rating': a['score'],
              'source': 'Jikan',
              'source_url': a['url'],
            }));
          }
        }
      } catch (_) {}

      // TVmaze supplies public TV show metadata; playback/audio is not included.
      try {
        final response = await client
            .get(Uri.parse('https://api.tvmaze.com/shows?page=0'))
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final shows = jsonDecode(response.body) as List;
          for (final raw in shows.take(60)) {
            final s = Map<String, dynamic>.from(raw as Map);
            final image = Map<String, dynamic>.from(s['image'] as Map? ?? {});
            final premiered = s['premiered']?.toString() ?? '';
            final rating = Map<String, dynamic>.from(s['rating'] as Map? ?? {});
            items.add(ContentItem.fromMap({
              'id': 'tvmaze-${s['id']}',
              'title': s['name'],
              'content_type': 'series',
              'synopsis': s['summary']?.toString().replaceAll(RegExp(r'<[^>]*>'), ''),
              'poster_url': image['original'] ?? image['medium'],
              'release_year': int.tryParse(premiered.split('-').first),
              'rating': rating['average'],
              'source': 'TVmaze',
              'source_url': s['url'],
            }));
          }
        }
      } catch (_) {}

      // Internet Archive provides public-domain movie catalogue metadata.
      try {
        final uri = Uri.https('archive.org', '/advancedsearch.php', {
          'q': 'mediatype:movies AND collection:feature_films',
          'fl[]': 'identifier,title,description,year',
          'rows': '50',
          'output': 'json',
        });
        final response =
            await client.get(uri).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final root = jsonDecode(response.body) as Map<String, dynamic>;
          final docs = (root['response'] as Map?)?['docs'] as List? ?? const [];
          for (final raw in docs) {
            final movie = Map<String, dynamic>.from(raw as Map);
            final identifier = movie['identifier']?.toString() ?? '';
            if (identifier.isEmpty) continue;
            items.add(ContentItem.fromMap({
              'id': 'archive-$identifier',
              'title': movie['title'] ?? identifier,
              'content_type': 'movie',
              'synopsis': movie['description'] is String
                  ? movie['description']
                  : null,
              'poster_url': 'https://archive.org/services/img/$identifier',
              'release_year': int.tryParse(movie['year']?.toString() ?? ''),
              'source': 'Internet Archive',
              'source_url': 'https://archive.org/details/$identifier',
            }));
          }
        }
      } catch (_) {}
    } finally {
      client.close();
    }

    return _deduplicate(items);
  }

  Future<List<SeasonItem>> loadSeasons(String contentId) async {
    if (_db == null) return const [];
    final rows = await _db!
        .from('seasons')
        .select('id,content_id,season_number,title,synopsis,poster_url')
        .eq('content_id', contentId)
        .order('season_number');
    return rows
        .map<SeasonItem>((row) => SeasonItem.fromMap(row))
        .toList(growable: false);
  }

  Future<List<EpisodeItem>> loadEpisodes(String seasonId) async {
    if (_db == null) return const [];
    final rows = await _db!
        .from('episodes')
        .select(
          'id,season_id,episode_number,title,synopsis,video_url,'
          'audio_language,subtitle_url,duration_seconds',
        )
        .eq('season_id', seasonId)
        .ilike('audio_language', '%hindi%')
        .order('episode_number');
    return rows
        .map<EpisodeItem>((row) => EpisodeItem.fromMap(row))
        .toList(growable: false);
  }
}
