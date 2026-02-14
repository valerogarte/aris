class YouTubeVideo {
  YouTubeVideo({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.channelId,
    required this.publishedAt,
    required this.thumbnailUrl,
    this.durationSeconds,
  });

  final String id;
  final String title;
  final String channelTitle;
  final String channelId;
  final DateTime publishedAt;
  final String thumbnailUrl;
  final int? durationSeconds;

  factory YouTubeVideo.fromPlaylistItem(
    Map<String, dynamic> item, {
    int? durationSeconds,
  }) {
    final snippet = (item['snippet'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final resource = (snippet['resourceId'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final thumbnails = (snippet['thumbnails'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    return YouTubeVideo(
      id: (resource['videoId'] as String?) ?? '',
      title: (snippet['title'] as String?) ?? 'Sin título',
      channelTitle: (snippet['videoOwnerChannelTitle'] as String?) ??
          (snippet['channelTitle'] as String?) ??
          'Canal',
      channelId: (snippet['videoOwnerChannelId'] as String?) ??
          (snippet['channelId'] as String?) ??
          '',
      publishedAt:
          DateTime.tryParse((snippet['publishedAt'] as String?) ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      thumbnailUrl: _pickThumbnail(thumbnails),
      durationSeconds: durationSeconds,
    );
  }

  factory YouTubeVideo.fromSearchItem(
    Map<String, dynamic> item, {
    int? durationSeconds,
  }) {
    final idMap = (item['id'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final snippet = (item['snippet'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final thumbnails = (snippet['thumbnails'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    return YouTubeVideo(
      id: (idMap['videoId'] as String?) ?? '',
      title: (snippet['title'] as String?) ?? 'Sin título',
      channelTitle: (snippet['channelTitle'] as String?) ?? 'Canal',
      channelId: (snippet['channelId'] as String?) ?? '',
      publishedAt:
          DateTime.tryParse((snippet['publishedAt'] as String?) ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      thumbnailUrl: _pickThumbnail(thumbnails),
      durationSeconds: durationSeconds,
    );
  }

  static String _pickThumbnail(Map<String, dynamic> thumbnails) {
    for (final key in ['maxres', 'high', 'medium', 'default']) {
      final data = thumbnails[key] as Map<String, dynamic>?;
      final url = data?['url'] as String?;
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    return '';
  }
}
