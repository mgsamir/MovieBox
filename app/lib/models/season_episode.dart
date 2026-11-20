class SeasonItem {
  final String id;
  final String contentId;
  final int number;
  final String title;
  final String? synopsis;
  final String? posterUrl;

  SeasonItem.fromMap(Map<String, dynamic> map)
      : id = map['id']?.toString() ?? '',
        contentId = map['content_id']?.toString() ?? '',
        number = int.tryParse(map['season_number']?.toString() ?? '') ?? 0,
        title = (map['title']?.toString().trim().isNotEmpty ?? false)
            ? map['title'].toString().trim()
            : 'Season ${map['season_number'] ?? ''}',
        synopsis = _optionalText(map['synopsis']),
        posterUrl = _optionalText(map['poster_url']);
}

class EpisodeItem {
  final String id;
  final String seasonId;
  final int number;
  final String title;
  final String? synopsis;
  final String videoUrl;
  final String audioLanguage;
  final String? subtitleUrl;
  final int? durationSeconds;

  EpisodeItem.fromMap(Map<String, dynamic> map)
      : id = map['id']?.toString() ?? '',
        seasonId = map['season_id']?.toString() ?? '',
        number = int.tryParse(map['episode_number']?.toString() ?? '') ?? 0,
        title = map['title']?.toString().trim().isNotEmpty == true
            ? map['title'].toString().trim()
            : 'Episode ${map['episode_number'] ?? ''}',
        synopsis = _optionalText(map['synopsis']),
        videoUrl = map['video_url']?.toString() ?? '',
        audioLanguage = map['audio_language']?.toString() ?? 'Hindi Dubbed',
        subtitleUrl = _optionalText(map['subtitle_url']),
        durationSeconds =
            int.tryParse(map['duration_seconds']?.toString() ?? '');
}

String? _optionalText(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
