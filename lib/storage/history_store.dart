import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../models/history_video.dart';
import '../models/youtube_video.dart';
import 'app_database.dart';

class HistoryStore {
  static const String _table = 'history_videos';

  Future<void> markWatched(YouTubeVideo video) async {
    final now = DateTime.now();
    await _upsert(video, watchedAt: now);
  }

  Future<void> markSummaryRequested(YouTubeVideo video) async {
    final now = DateTime.now();
    await _upsert(video, summaryRequestedAt: now);
  }

  Future<List<HistoryVideo>> fetchAll() async {
    final db = await AppDatabase.instance.open();
    final rows = await db.query(
      _table,
      orderBy: 'last_activity_at DESC',
    );
    return rows.map(_mapRow).toList();
  }

  Future<List<HistoryVideo>> fetchPage({
    required int limit,
    required int offset,
  }) async {
    final db = await AppDatabase.instance.open();
    final rows = await db.query(
      _table,
      orderBy: 'last_activity_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_mapRow).toList();
  }

  Future<void> deleteByVideoId(String videoId) async {
    final trimmed = videoId.trim();
    if (trimmed.isEmpty) return;
    final db = await AppDatabase.instance.open();
    await db.delete(
      _table,
      where: 'video_id = ?',
      whereArgs: [trimmed],
    );
  }

  Future<void> _upsert(
    YouTubeVideo video, {
    DateTime? watchedAt,
    DateTime? summaryRequestedAt,
  }) async {
    final db = await AppDatabase.instance.open();
    final existing = await db.query(
      _table,
      where: 'video_id = ?',
      whereArgs: [video.id],
      limit: 1,
    );
    DateTime? mergedWatchedAt = watchedAt;
    DateTime? mergedSummaryAt = summaryRequestedAt;
    if (existing.isNotEmpty) {
      final row = existing.first;
      final existingWatched = row['watched_at'] as int?;
      final existingSummary = row['summary_requested_at'] as int?;
      if (mergedWatchedAt == null && existingWatched != null) {
        mergedWatchedAt =
            DateTime.fromMillisecondsSinceEpoch(existingWatched);
      }
      if (mergedSummaryAt == null && existingSummary != null) {
        mergedSummaryAt =
            DateTime.fromMillisecondsSinceEpoch(existingSummary);
      }
    }

    final watchedMillis = mergedWatchedAt?.millisecondsSinceEpoch;
    final summaryMillis = mergedSummaryAt?.millisecondsSinceEpoch;
    final lastActivityMillis = math.max(
      watchedMillis ?? 0,
      summaryMillis ?? 0,
    );

    await db.insert(
      _table,
      {
        'video_id': video.id,
        'title': video.title,
        'channel_id': video.channelId,
        'channel_title': video.channelTitle,
        'thumbnail_url': video.thumbnailUrl,
        'published_at': video.publishedAt.toIso8601String(),
        'duration_seconds': video.durationSeconds,
        'watched_at': watchedMillis,
        'summary_requested_at': summaryMillis,
        'last_activity_at': lastActivityMillis > 0
            ? lastActivityMillis
            : DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  HistoryVideo _mapRow(Map<String, Object?> row) {
    final publishedRaw = row['published_at'] as String?;
    final publishedAt = publishedRaw == null || publishedRaw.isEmpty
        ? null
        : DateTime.tryParse(publishedRaw);
    final watchedMillis = row['watched_at'] as int?;
    final summaryMillis = row['summary_requested_at'] as int?;
    final lastMillis = (row['last_activity_at'] as int?) ?? 0;
    final lastAt = lastMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(lastMillis)
        : DateTime.fromMillisecondsSinceEpoch(0);
    return HistoryVideo(
      videoId: row['video_id'] as String? ?? '',
      title: row['title'] as String? ?? 'Sin título',
      channelId: row['channel_id'] as String? ?? '',
      channelTitle: row['channel_title'] as String? ?? 'Canal',
      thumbnailUrl: row['thumbnail_url'] as String? ?? '',
      publishedAt: publishedAt,
      durationSeconds: row['duration_seconds'] as int?,
      watchedAt: watchedMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(watchedMillis),
      summaryRequestedAt: summaryMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(summaryMillis),
      lastActivityAt: lastAt,
    );
  }
}
