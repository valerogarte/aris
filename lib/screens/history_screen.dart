import 'package:flutter/material.dart';

import '../models/history_video.dart';
import '../models/youtube_video.dart';
import '../services/ai_cost_tracker.dart';
import '../services/quota_tracker.dart';
import '../storage/channel_store.dart';
import '../storage/expiring_cache_store.dart';
import '../storage/history_store.dart';
import '../ui/channel_avatar.dart';
import 'video_detail_screen.dart';

String formatRelativeTime(DateTime date) {
  final now = DateTime.now().toLocal();
  final target = date.toLocal();
  var diff = now.difference(target);
  if (diff.isNegative) {
    diff = Duration.zero;
  }
  final minutes = diff.inMinutes;
  if (minutes < 60) {
    if (minutes <= 1) return 'hace 1 minuto';
    return 'hace $minutes minutos';
  }
  final hours = diff.inHours;
  if (hours < 24) {
    if (hours == 1) return 'hace 1 hora';
    return 'hace $hours horas';
  }
  final days = diff.inDays;
  if (days < 7) {
    if (days == 1) return 'hace 1 día';
    return 'hace $days días';
  }
  if (days < 30) {
    final weeks = (days / 7).floor();
    if (weeks <= 1) return 'hace 1 semana';
    return 'hace $weeks semanas';
  }
  if (days < 365) {
    final months = (days / 30).floor();
    if (months <= 1) return 'hace 1 mes';
    return 'hace $months meses';
  }
  final years = (days / 365).floor();
  if (years <= 1) return 'hace 1 año';
  return 'hace $years años';
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.accessToken,
    this.quotaTracker,
    this.aiCostTracker,
  });

  final String accessToken;
  final QuotaTracker? quotaTracker;
  final AiCostTracker? aiCostTracker;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistoryStore _historyStore = HistoryStore();
  final ChannelStore _channelStore = ChannelStore();
  final ExpiringCacheStore _avatarCache =
      ExpiringCacheStore('channel_avatars');
  List<HistoryVideo> _items = const [];
  Map<String, String> _channelAvatars = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
    });
    final items = await _historyStore.fetchAll();
    final avatarMap = await _loadChannelAvatars(items);
    if (!mounted) return;
    setState(() {
      _items = items;
      _channelAvatars = avatarMap;
      _loading = false;
    });
  }

  Future<Map<String, String>> _loadChannelAvatars(
    List<HistoryVideo> items,
  ) async {
    final ids = items
        .map((item) => item.channelId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return {};
    final entries = <String, String>{};
    for (final id in ids) {
      final channel = await _channelStore.getById(id);
      final url = channel?.thumbnailUrl;
      if (url != null && url.isNotEmpty) {
        entries[id] = url;
        continue;
      }
      final cached = await _avatarCache.get(id);
      if (cached != null && cached.isNotEmpty) {
        entries[id] = cached;
      }
    }
    return entries;
  }

  void _openVideo(HistoryVideo item) {
    final publishedAt = item.publishedAt ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final video = YouTubeVideo(
      id: item.videoId,
      title: item.title,
      channelTitle: item.channelTitle,
      channelId: item.channelId,
      publishedAt: publishedAt,
      thumbnailUrl: item.thumbnailUrl,
      durationSeconds: item.durationSeconds,
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => VideoDetailScreen(
              video: video,
              accessToken: widget.accessToken,
              channelAvatarUrl: _channelAvatars[item.channelId] ?? '',
              quotaTracker: widget.quotaTracker,
              aiCostTracker: widget.aiCostTracker,
            ),
          ),
        )
        .then((_) => _loadHistory());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          'Aún no hay vídeos en el historial.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _items[index];
          return _HistoryCard(
            item: item,
            channelAvatarUrl: _channelAvatars[item.channelId] ?? '',
            onTap: () => _openVideo(item),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.channelAvatarUrl,
    required this.onTap,
  });

  final HistoryVideo item;
  final String channelAvatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
    );
    final publishedAt = item.publishedAt;
    final secondary = publishedAt == null
        ? item.channelTitle
        : '${item.channelTitle} • ${formatRelativeTime(publishedAt)}';

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _Thumbnail(url: item.thumbnailUrl),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    ChannelAvatar(
                      name: item.channelTitle,
                      imageUrl: channelAvatarUrl,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (item.watchedAt != null)
                          const Icon(
                            Icons.play_circle,
                            color: Color(0xFFFA1021),
                            size: 16,
                          ),
                        if (item.summaryRequestedAt != null) ...[
                          if (item.watchedAt != null)
                            const SizedBox(width: 6),
                          const Icon(
                            Icons.auto_fix_high,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        secondary,
                        style: subtitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.history,
                  color: Colors.white54,
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        color: const Color(0xFF1E1E1E),
        alignment: Alignment.center,
        child: const Icon(
          Icons.history,
          color: Colors.white70,
          size: 40,
        ),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, _, __) => Container(
        color: const Color(0xFF1E1E1E),
        alignment: Alignment.center,
        child: const Icon(
          Icons.history,
          color: Colors.white70,
          size: 40,
        ),
      ),
    );
  }
}
