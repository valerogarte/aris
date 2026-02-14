import 'package:sqflite/sqflite.dart';

import '../models/youtube_channel.dart';
import 'app_database.dart';

class ChannelStore {
  static const String _table = 'channels';

  Future<void> upsertChannels(List<YouTubeChannel> channels) async {
    if (channels.isEmpty) return;
    final db = await AppDatabase.instance.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final channel in channels) {
      if (channel.channelId.isEmpty) continue;
      batch.insert(
        _table,
        {
          'channel_id': channel.channelId,
          'title': channel.title,
          'description': channel.description,
          'thumbnail_url': channel.thumbnailUrl,
          'published_at': channel.publishedAt,
          'custom_url': channel.customUrl,
          'country': channel.country,
          'uploads_playlist_id': channel.uploadsPlaylistId,
          'subscriber_count': channel.subscriberCount,
          'view_count': channel.viewCount,
          'video_count': channel.videoCount,
          'raw_json': channel.rawJson,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<YouTubeChannel>> fetchAll() async {
    final db = await AppDatabase.instance.open();
    final rows = await db.query(_table, orderBy: 'title COLLATE NOCASE');
    return rows.map(_mapRow).toList();
  }

  Future<YouTubeChannel?> getById(String channelId) async {
    final db = await AppDatabase.instance.open();
    final rows = await db.query(
      _table,
      where: 'channel_id = ?',
      whereArgs: [channelId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapRow(rows.first);
  }

  Future<Set<String>> existingIds(Iterable<String> channelIds) async {
    final ids = channelIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return {};
    final db = await AppDatabase.instance.open();
    final rows = await db.query(
      _table,
      columns: const ['channel_id'],
      where:
          'channel_id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
    return rows.map((row) => row['channel_id'] as String).toSet();
  }

  YouTubeChannel _mapRow(Map<String, Object?> row) {
    return YouTubeChannel(
      channelId: row['channel_id'] as String? ?? '',
      title: row['title'] as String? ?? 'Canal',
      description: row['description'] as String?,
      thumbnailUrl: row['thumbnail_url'] as String?,
      publishedAt: row['published_at'] as String?,
      customUrl: row['custom_url'] as String?,
      country: row['country'] as String?,
      uploadsPlaylistId: row['uploads_playlist_id'] as String?,
      subscriberCount: row['subscriber_count'] as int?,
      viewCount: row['view_count'] as int?,
      videoCount: row['video_count'] as int?,
      rawJson: row['raw_json'] as String?,
    );
  }
}
