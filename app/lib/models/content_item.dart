class ContentItem {
  final String id, title, type;
  final String? synopsis, posterUrl, videoUrl;
  final int? year;
  ContentItem.fromMap(Map<String,dynamic> m): id=m['id'].toString(),
    title=m['title'] ?? '', type=m['content_type'] ?? 'movie',
    synopsis=m['synopsis'], posterUrl=m['poster_url'], videoUrl=m['video_url'],
    year=m['release_year'];
}
