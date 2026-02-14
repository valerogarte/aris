import 'package:flutter/material.dart';

import '../models/youtube_video.dart';
import '../services/ai_cost_tracker.dart';
import '../services/quota_tracker.dart';
import '../services/youtube_api_service.dart';
import '../storage/ai_settings_store.dart';
import '../storage/expiring_cache_store.dart';
import '../ui/channel_avatar.dart';
import 'channel_videos_screen.dart';
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

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.accessToken,
    this.quotaTracker,
    this.aiCostTracker,
    this.onRefreshToken,
  });

  final String accessToken;
  final QuotaTracker? quotaTracker;
  final AiCostTracker? aiCostTracker;
  final Future<String?> Function({bool interactive})? onRefreshToken;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late YouTubeApiService _api;
  late String _accessToken;
  final TextEditingController _queryController = TextEditingController();
  final AiSettingsStore _aiSettingsStore = AiSettingsStore();
  final ExpiringCacheStore _avatarCache = ExpiringCacheStore('channel_avatars');
  final ExpiringCacheStore _summaryCache = ExpiringCacheStore('summaries');

  List<YouTubeVideo> _videos = const [];
  Map<String, String> _channelAvatars = {};
  Map<String, bool> _summaryByVideoId = {};
  bool _loading = false;
  bool _loadingAvatars = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _accessToken = widget.accessToken;
    _api = YouTubeApiService(
      accessToken: _accessToken,
      quotaTracker: widget.quotaTracker,
    );
  }

  @override
  void dispose() {
    _api.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _refreshAccessToken({required bool interactive}) async {
    if (widget.onRefreshToken == null) return;
    final token = await widget.onRefreshToken!(interactive: interactive);
    if (!mounted || token == null || token.isEmpty) return;
    if (token == _accessToken) return;
    _api.dispose();
    _accessToken = token;
    _api = YouTubeApiService(
      accessToken: _accessToken,
      quotaTracker: widget.quotaTracker,
    );
  }

  Future<void> _search({bool userInitiated = false}) async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un título para buscar.')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _videos = const [];
      _summaryByVideoId = {};
    });

    try {
      await _refreshAccessToken(interactive: userInitiated);
      final page = await _api.searchVideos(query: query);
      if (!mounted) return;
      setState(() {
        _videos = page.videos;
        _loading = false;
      });
      await _loadChannelAvatars(page.videos);
      await _loadSummaryFlags(page.videos);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo completar la búsqueda.\n$error';
        _loading = false;
      });
    }
  }

  Future<void> _loadChannelAvatars(List<YouTubeVideo> videos) async {
    if (_loadingAvatars) return;
    final ids = videos
        .map((video) => video.channelId)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;

    final cached = <String, String>{};
    final missing = <String>[];
    for (final id in ids) {
      if (_channelAvatars.containsKey(id)) continue;
      final cachedUrl = await _avatarCache.get(id);
      if (cachedUrl != null && cachedUrl.isNotEmpty) {
        cached[id] = cachedUrl;
      } else {
        missing.add(id);
      }
    }

    if (cached.isNotEmpty && mounted) {
      setState(() {
        _channelAvatars = {
          ..._channelAvatars,
          ...cached,
        };
      });
    }

    if (missing.isEmpty) return;

    _loadingAvatars = true;
    try {
      final fetched = await _api.fetchChannelThumbnails(missing);
      if (!mounted) return;
      if (fetched.isNotEmpty) {
        setState(() {
          _channelAvatars = {
            ..._channelAvatars,
            ...fetched,
          };
        });
        const ttl = Duration(days: 7);
        for (final entry in fetched.entries) {
          await _avatarCache.set(entry.key, entry.value, ttl);
        }
      }
    } finally {
      _loadingAvatars = false;
    }
  }

  Future<void> _loadSummaryFlags(List<YouTubeVideo> videos) async {
    if (videos.isEmpty) {
      if (mounted) {
        setState(() {
          _summaryByVideoId = {};
        });
      }
      return;
    }
    try {
      final settings = await _aiSettingsStore.load();
      if (!mounted) return;
      final entries = await Future.wait(
        videos.map((video) async {
          final id = video.id.trim();
          if (id.isEmpty) {
            return const MapEntry<String, bool>('', false);
          }
          final key = '${settings.provider}:${settings.model}:$id';
          final summary = await _summaryCache.get(key);
          final hasSummary = summary != null && summary.trim().isNotEmpty;
          return MapEntry(id, hasSummary);
        }),
      );
      if (!mounted) return;
      final map = <String, bool>{};
      for (final entry in entries) {
        if (entry.key.isEmpty) continue;
        map[entry.key] = entry.value;
      }
      setState(() {
        _summaryByVideoId = map;
      });
    } catch (_) {
      // Ignore summary flag errors.
    }
  }

  void _openVideo(YouTubeVideo video) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => VideoDetailScreen(
              video: video,
              accessToken: _accessToken,
              channelAvatarUrl: _channelAvatars[video.channelId] ?? '',
              quotaTracker: widget.quotaTracker,
              aiCostTracker: widget.aiCostTracker,
            ),
          ),
        )
        .then((_) => _loadSummaryFlags(_videos));
  }

  void _openChannelVideos(YouTubeVideo video) {
    final channelId = video.channelId.trim();
    if (channelId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChannelVideosScreen(
          accessToken: _accessToken,
          channelId: channelId,
          channelTitle: video.channelTitle,
          channelAvatarUrl: _channelAvatars[video.channelId] ?? '',
          quotaTracker: widget.quotaTracker,
          aiCostTracker: widget.aiCostTracker,
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _search(userInitiated: true),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_videos.isEmpty) {
      return const Center(child: Text('No hay resultados.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _videos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final video = _videos[index];
        return _VideoCard(
          video: video,
          channelAvatarUrl: _channelAvatars[video.channelId] ?? '',
          hasSummary: _summaryByVideoId[video.id] ?? false,
          onTap: () => _openVideo(video),
          onChannelTap: () => _openChannelVideos(video),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryController.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _queryController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(userInitiated: true),
                  onChanged: (_) {
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar vídeos',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _queryController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : () => _search(userInitiated: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFA1021),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.video,
    required this.channelAvatarUrl,
    required this.hasSummary,
    required this.onTap,
    required this.onChannelTap,
  });

  final YouTubeVideo video;
  final String channelAvatarUrl;
  final bool hasSummary;
  final VoidCallback onTap;
  final VoidCallback onChannelTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white70,
    );
    final durationLabel = _formatDuration(video.durationSeconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _Thumbnail(
              url: video.thumbnailUrl,
              durationLabel: durationLabel,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  InkWell(
                    onTap: onChannelTap,
                    customBorder: const CircleBorder(),
                    child: ChannelAvatar(
                      name: video.channelTitle,
                      imageUrl: channelAvatarUrl,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (hasSummary)
                    const Icon(
                      Icons.auto_fix_high,
                      color: Color(0xFFFA1021),
                      size: 16,
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: onTap,
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
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onTap,
                child: const Icon(
                  Icons.more_vert,
                  color: Colors.white54,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ],
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
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
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
