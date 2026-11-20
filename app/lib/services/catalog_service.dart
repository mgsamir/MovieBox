import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/content_item.dart';
class CatalogService {
  final _db=Supabase.instance.client;
  Future<List<ContentItem>> load(String type,{String query=''}) async {
    var q=_db.from('content').select().eq('content_type',type);
    if(query.trim().isNotEmpty) q=q.ilike('title','%$query%');
    final rows=await q.order('title').limit(100);
    return rows.map<ContentItem>((e)=>ContentItem.fromMap(e)).toList();
  }
}
