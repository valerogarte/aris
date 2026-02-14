import 'dart:convert';

class YouTubeChannel {
  YouTubeChannel({
    required this.channelId,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.publishedAt,
    this.customUrl,
    this.country,
    this.uploadsPlaylistId,
    this.subscriberCount,
    this.viewCount,
    this.videoCount,
    this.rawJson,
  });

  final String channelId;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String? publishedAt;
  final String? customUrl;
  final String? country;
  final String? uploadsPlaylistId;
  final int? subscriberCount;
  final int? viewCount;
  final int? videoCount;
  final String? rawJson;

  factory YouTubeChannel.fromChannelItem(Map<String, dynamic> item) {
    final id = (item['id'] as String?) ?? '';
    final snippet = (item['snippet'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final thumbnails = (snippet['thumbnails'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final contentDetails =
        (item['contentDetails'] as Map<String, dynamic>?) ??
            const <String, dynamic>{};
    final related =
        (contentDetails['relatedPlaylists'] as Map<String, dynamic>?) ??
            const <String, dynamic>{};
    final statistics = (item['statistics'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    return YouTubeChannel(
      channelId: id,
      title: (snippet['title'] as String?) ?? 'Canal',
      description: snippet['description'] as String?,
      thumbnailUrl: _pickThumbnail(thumbnails),
      publishedAt: snippet['publishedAt'] as String?,
      customUrl: snippet['customUrl'] as String?,
      country: snippet['country'] as String?,
      uploadsPlaylistId: related['uploads'] as String?,
      subscriberCount: _parseInt(statistics['subscriberCount']),
      viewCount: _parseInt(statistics['viewCount']),
      videoCount: _parseInt(statistics['videoCount']),
      rawJson: jsonEncode(item),
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

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is num) return value.toInt();
    return null;
  }
}
