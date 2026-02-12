import 'package:flutter/material.dart';
import '../models/youtube_video.dart';
import '../services/youtube_api_service.dart';
import '../services/quota_tracker.dart';
import '../storage/expiring_cache_store.dart';
import '../services/ai_cost_tracker.dart';
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

class ChannelVideosScreen extends StatefulWidget {
  const ChannelVideosScreen({
    super.key,
    required this.accessToken,
    required this.channelId,
    required this.channelTitle,
    this.channelAvatarUrl = '',
    this.quotaTracker,
    this.aiCostTracker,
  });

  final String accessToken;
  final String channelId;
  final String channelTitle;
  final String channelAvatarUrl;
  final QuotaTracker? quotaTracker;
  final AiCostTracker? aiCostTracker;

  @override
  State<ChannelVideosScreen> createState() => _ChannelVideosScreenState();
}

class _ChannelVideosScreenState extends State<ChannelVideosScreen> {
  static const Duration _cacheTtl = Duration(days: 2);
  static const double _loadMoreThreshold = 320;

  late YouTubeApiService _api;
  late String _accessToken;
  final ScrollController _scrollController = ScrollController();
  final ExpiringCacheStore _avatarCache =
      ExpiringCacheStore('channel_avatars');

  String _channelAvatarUrl = '';
  bool _loadingAvatar = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _nextPageToken;
  String? _uploadsPlaylistId;
  List<YouTubeVideo> _videos = const [];
  final Set<String> _videoIds = {};

  @override
  void initState() {
    super.initState();
    _accessToken = widget.accessToken;
    _api = YouTubeApiService(
      accessToken: _accessToken,
      quotaTracker: widget.quotaTracker,
    );
    _channelAvatarUrl = widget.channelAvatarUrl;
    _loadChannelAvatar();
    _loadVideos(reset: true);
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _api.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_loading || _loadingMore) return;
    final nextToken = _nextPageToken;
    if (nextToken == null || nextToken.isEmpty) return;
    if (!_scrollController.hasClients) return;
    final remaining = _scrollController.position.extentAfter;
    if (remaining <= _loadMoreThreshold) {
      _loadVideos(reset: false);
    }
  }

  Future<void> _loadChannelAvatar() async {
    if (_loadingAvatar) return;
    if (_channelAvatarUrl.isNotEmpty) return;
    final channelId = widget.channelId.trim();
    if (channelId.isEmpty) return;
    _loadingAvatar = true;
    try {
      final cached = await _avatarCache.get(channelId);
      if (!mounted) return;
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _channelAvatarUrl = cached;
        });
        return;
      }
      final fetched = await _api.fetchChannelThumbnails([channelId]);
      if (!mounted) return;
      final url = fetched[channelId];
      if (url != null && url.isNotEmpty) {
        await _avatarCache.set(channelId, url, _cacheTtl);
        if (mounted) {
          setState(() {
            _channelAvatarUrl = url;
          });
        }
      }
    } catch (_) {
      // Ignore avatar errors.
    } finally {
      _loadingAvatar = false;
    }
  }

  Future<void> _loadVideos({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _videos = const [];
        _videoIds.clear();
        _nextPageToken = null;
      });
    } else {
      final nextToken = _nextPageToken;
      if (nextToken == null || nextToken.isEmpty) return;
      if (_loadingMore) return;
      setState(() {
        _loadingMore = true;
      });
    }

    try {
      final page = await _api.fetchChannelUploads(
        channelId: widget.channelId,
        uploadsPlaylistId: _uploadsPlaylistId,
        pageToken: reset ? null : _nextPageToken,
        maxResults: 20,
      );
      if (!mounted) return;
      final incoming = <YouTubeVideo>[];
      for (final video in page.videos) {
        if (_videoIds.add(video.id)) {
          incoming.add(video);
        }
      }
      setState(() {
        _uploadsPlaylistId = page.uploadsPlaylistId ?? _uploadsPlaylistId;
        _nextPageToken = page.nextPageToken;
        if (reset) {
          _videos = incoming;
          _loading = false;
        } else {
          _videos = [..._videos, ...incoming];
          _loadingMore = false;
        }
      });
    } catch (error) {
      if (!mounted) return;
      if (reset) {
        setState(() {
          _error = 'No se pudieron cargar los vídeos.\n$error';
          _loading = false;
        });
      } else {
        setState(() {
          _loadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron cargar más vídeos.')),
        );
      }
    }
  }

  void _openVideo(YouTubeVideo video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoDetailScreen(
          video: video,
          accessToken: _accessToken,
          channelAvatarUrl: _channelAvatarUrl,
          quotaTracker: widget.quotaTracker,
          aiCostTracker: widget.aiCostTracker,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.channelTitle.trim().isEmpty ? 'Canal' : widget.channelTitle;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _loadVideos(reset: true),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_videos.isEmpty) {
      return const Center(
        child: Text('No hay vídeos disponibles en este canal.'),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadVideos(reset: true),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _videos.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == _videos.length) {
            if (_loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (_nextPageToken == null || _nextPageToken!.isEmpty) {
              return const SizedBox(height: 12);
            }
            return const SizedBox(height: 12);
          }
          final video = _videos[index];
          return _ChannelVideoCard(
            video: video,
            channelAvatarUrl: _channelAvatarUrl,
            onTap: () => _openVideo(video),
          );
        },
      ),
    );
  }

}

class _ChannelVideoCard extends StatelessWidget {
  const _ChannelVideoCard({
    required this.video,
    required this.channelAvatarUrl,
    required this.onTap,
  });

  final YouTubeVideo video;
  final String channelAvatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
    );
    final durationLabel = _formatDuration(video.durationSeconds);

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _Thumbnail(
              url: video.thumbnailUrl,
              durationLabel: durationLabel,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChannelAvatar(
                  name: video.channelTitle,
                  imageUrl: channelAvatarUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${video.channelTitle} • ${formatRelativeTime(video.publishedAt)}',
                        style: subtitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.more_vert,
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
  const _Thumbnail({
    required this.url,
    this.durationLabel,
  });

  final String url;
  final String? durationLabel;

  @override
  Widget build(BuildContext context) {
    final showDuration = durationLabel != null && durationLabel!.isNotEmpty;
    if (url.isEmpty) {
      return Container(
        color: const Color(0xFF1E1E1E),
        alignment: Alignment.center,
        child: const Icon(
          Icons.play_circle_outline,
          color: Colors.white70,
          size: 40,
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, _, __) => Container(
              color: const Color(0xFF1E1E1E),
              alignment: Alignment.center,
              child: const Icon(
                Icons.play_circle_outline,
                color: Colors.white70,
                size: 40,
              ),
            ),
          ),
        ),
        if (showDuration)
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xB8000000),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                durationLabel!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String? _formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return null;
  final total = seconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final secs = total % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = secs.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$mm:$ss';
  }
  return '$minutes:$ss';
}
