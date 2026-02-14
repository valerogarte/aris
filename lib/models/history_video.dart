class HistoryVideo {
  const HistoryVideo({
    required this.videoId,
    required this.title,
    required this.channelId,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.publishedAt,
    required this.durationSeconds,
    required this.watchedAt,
    required this.summaryRequestedAt,
    required this.lastActivityAt,
  });

  final String videoId;
  final String title;
  final String channelId;
  final String channelTitle;
  final String thumbnailUrl;
  final DateTime? publishedAt;
  final int? durationSeconds;
  final DateTime? watchedAt;
  final DateTime? summaryRequestedAt;
  final DateTime lastActivityAt;
}
