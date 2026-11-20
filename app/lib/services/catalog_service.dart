import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/content_item.dart';

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
        );

    if (type != null && type != 'all') {
      request = request.eq('content_type', type);
    }
    if (query.trim().isNotEmpty) {
      request = request.ilike('title', '%${query.trim()}%');
    }

    final rows = await request.order('title').limit(limit);
    return rows
        .map<ContentItem>((row) => ContentItem.fromMap(row))
        .toList(growable: false);
  }
}
