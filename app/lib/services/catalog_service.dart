import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/content_item.dart';
import '../models/season_episode.dart';

class CatalogService {
  final SupabaseClient _db;

  CatalogService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  Future<List<ContentItem>> loadAll({
    String query = '',
    String? type,
    int limit = 150,
  }) async {
    var request = _db
        .from('content')
        .select(
          'id,title,content_type,synopsis,poster_url,backdrop_url,'
          'release_year,rating,language,source,source_url,video_url',
        )
        .ilike('language', '%hindi%');

    if (type != null && type != 'all') {
      request = request.eq('content_type', type);
    }
    if (query.trim().isNotEmpty) {
      request = request.ilike('title', '%${query.trim()}%');
    }

    final rows = await request.order('title').limit(limit);
    final unique = <String, ContentItem>{};
    for (final row in rows) {
      final item = ContentItem.fromMap(row);
      if (item.id.isNotEmpty && item.title.trim().isNotEmpty) {
        unique.putIfAbsent(item.title.trim().toLowerCase(), () => item);
      }
    }
    return unique.values.toList(growable: false);
  }

  Future<List<SeasonItem>> loadSeasons(String contentId) async {
    final rows = await _db
        .from('seasons')
        .select('id,content_id,season_number,title,synopsis,poster_url')
        .eq('content_id', contentId)
        .order('season_number');
    return rows
        .map<SeasonItem>((row) => SeasonItem.fromMap(row))
        .toList(growable: false);
  }

  Future<List<EpisodeItem>> loadEpisodes(String seasonId) async {
    final rows = await _db
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
