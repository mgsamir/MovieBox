class ContentItem {
  final String id;
  final String title;
  final String type;
  final String? synopsis;
  final String? posterUrl;
  final String? backdropUrl;
  final String? videoUrl;
  final String? language;
  final String? source;
  final String? sourceUrl;
  final int? year;
  final double? rating;

  ContentItem.fromMap(Map<String, dynamic> map)
      : id = _stringValue(map['id']) ?? '',
        title = _stringValue(map['title']) ?? 'Untitled',
        type = _stringValue(map['content_type']) ?? 'movie',
        synopsis = _stringValue(map['synopsis']),
        posterUrl = _stringValue(map['poster_url']),
        backdropUrl = _stringValue(map['backdrop_url']),
        videoUrl = _stringValue(map['video_url']),
        language = _stringValue(map['language']),
        source = _stringValue(map['source']),
        sourceUrl = _stringValue(map['source_url']),
        year = int.tryParse(map['release_year']?.toString() ?? ''),
        rating = double.tryParse(map['rating']?.toString() ?? '');
}

String? _stringValue(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
