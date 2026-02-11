class YouTubeSubscription {
  YouTubeSubscription({
    required this.channelId,
    required this.title,
    required this.thumbnailUrl,
  });

  final String channelId;
  final String title;
  final String thumbnailUrl;

  factory YouTubeSubscription.fromSubscriptionItem(Map<String, dynamic> item) {
    final snippet = (item['snippet'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final resource = (snippet['resourceId'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final thumbnails = (snippet['thumbnails'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    return YouTubeSubscription(
      channelId: (resource['channelId'] as String?) ?? '',
      title: (snippet['title'] as String?) ?? 'Canal',
      thumbnailUrl: _pickThumbnail(thumbnails),
    );
  }

  static String _pickThumbnail(Map<String, dynamic> thumbnails) {
    for (final key in ['high', 'medium', 'default']) {
      final data = thumbnails[key] as Map<String, dynamic>?;
      final url = data?['url'] as String?;
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    return '';
  }
}
