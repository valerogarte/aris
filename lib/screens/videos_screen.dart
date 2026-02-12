import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../models/youtube_video.dart';
import '../services/youtube_api_service.dart';
import 'video_detail_screen.dart';
import '../services/quota_tracker.dart';
import '../storage/subscription_lists_store.dart';
import '../storage/expiring_cache_store.dart';
import '../storage/ai_settings_store.dart';
import '../ui/list_icons.dart';
import '../services/ai_cost_tracker.dart';
import '../ui/channel_avatar.dart';

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

class VideosScreen extends StatefulWidget {
  const VideosScreen({
    super.key,
    required this.accessToken,
    this.quotaTracker,
    this.onRefreshToken,
    this.listsVersion,
    this.aiCostTracker,
  });

  final String accessToken;
  final QuotaTracker? quotaTracker;
  final Future<String?> Function({bool interactive})? onRefreshToken;
  final ValueListenable<int>? listsVersion;
  final AiCostTracker? aiCostTracker;

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  late YouTubeApiService _api;
  final SubscriptionListsStore _listsStore = SubscriptionListsStore();
  final AiSettingsStore _aiSettingsStore = AiSettingsStore();
  late String _accessToken;
  bool _loading = true;
  String? _error;
  List<YouTubeVideo> _videos = const [];
  List<SubscriptionList> _lists = const [];
  Map<String, Set<String>> _assignments = {};
  final ExpiringCacheStore _avatarCache = ExpiringCacheStore('channel_avatars');
  final ExpiringCacheStore _summaryCache = ExpiringCacheStore('summaries');
  Map<String, String> _channelAvatars = {};
  Map<String, bool> _summaryByVideoId = {};
  bool _loadingAvatars = false;
  String? _selectedListId;
  int? _selectedListChannels;
  VoidCallback? _listsVersionListener;
  final ScrollController _listsScrollController = ScrollController();
  final Map<String, GlobalKey> _listChipKeys = {};
  String? _lastScrolledListId;

  @override
  void initState() {
    super.initState();
    _accessToken = widget.accessToken;
    _api = YouTubeApiService(
      accessToken: _accessToken,
      quotaTracker: widget.quotaTracker,
    );
    _loadVideos();
    _listsVersionListener = () {
      _handleListsVersionChanged();
    };
    widget.listsVersion?.addListener(_listsVersionListener!);
    _listsScrollController.addListener(() {
      // keep controller alive; offset is preserved automatically
    });
  }

  @override
  void didUpdateWidget(covariant VideosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadLists();
  }

  @override
  void dispose() {
    if (_listsVersionListener != null) {
      widget.listsVersion?.removeListener(_listsVersionListener!);
    }
    _listsScrollController.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    try {
      final data = await _listsStore.load();
      if (!mounted) return;
      final listIds = data.lists.map((list) => list.id).toSet();
      setState(() {
        _lists = data.lists;
        _assignments = data.assignments;
        if (_selectedListId != null && !listIds.contains(_selectedListId)) {
          _selectedListId = null;
          _selectedListChannels = null;
        }
        if (_selectedListId == null && data.lists.isNotEmpty) {
          _selectedListId = data.lists.first.id;
        }
        _listChipKeys.removeWhere((key, _) => !listIds.contains(key));
        for (final list in data.lists) {
          _listChipKeys.putIfAbsent(list.id, () => GlobalKey());
        }
      });
      _scrollToSelectedChip();
    } catch (_) {
      // No-op: listas no bloquean la pantalla de videos.
    }
  }

  Future<void> _handleListsVersionChanged() async {
    await _loadLists();
    if (!mounted) return;
    if (_selectedListId != null) {
      await _loadVideos(userInitiated: false, listId: _selectedListId);
    }
  }

  void _scrollToSelectedChip({bool animate = true}) {
    final selectedId = _selectedListId;
    if (selectedId == null) return;
    if (_lastScrolledListId == selectedId && _listsScrollController.hasClients) {
      return;
    }
    final key = _listChipKeys[selectedId];
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
        curve: Curves.easeOut,
      );
      _lastScrolledListId = selectedId;
    });
  }

  bool _hasAssignments(String listId) {
    final channels = _assignments[listId];
    return channels != null && channels.isNotEmpty;
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

  Future<void> _loadVideos({
    bool userInitiated = false,
    String? listId,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _refreshAccessToken(interactive: userInitiated);
      SubscriptionListsData? listsData;
      try {
        listsData = await _listsStore.load();
      } catch (_) {
        listsData = null;
      }

      final lists = listsData?.lists ?? _lists;
      final assignments = listsData?.assignments ?? _assignments;
      var activeListId = listId ?? _selectedListId;
      if (activeListId == null && lists.isNotEmpty) {
        activeListId = lists.first.id;
      }
      if (activeListId != null &&
          !lists.any((list) => list.id == activeListId)) {
        activeListId = null;
      }

      final selectedChannels = activeListId == null
          ? null
          : (assignments[activeListId] ?? <String>{});

      final videos = activeListId == null
          ? await _api.fetchRecentVideosFromSubscriptions()
          : selectedChannels!.isEmpty
              ? <YouTubeVideo>[]
              : await _api.fetchRecentVideosForChannels(
                  selectedChannels.toList(),
                );
      if (!mounted) return;
      setState(() {
        if (listsData != null) {
          _lists = lists;
          _assignments = assignments;
        }
        _selectedListId = activeListId;
        _selectedListChannels = selectedChannels?.length;
        _videos = videos;
        _loading = false;
      });
      await _loadChannelAvatars(videos);
      await _loadSummaryFlags(videos);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los vídeos.\n$error';
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

  Future<void> _handleListTap(String listId) async {
    if (_selectedListId == listId) return;
    final next = listId;
    setState(() {
      _selectedListId = next;
    });
    _scrollToSelectedChip();
    await _loadVideos(userInitiated: true, listId: next);
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody(context);
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadVideos,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_videos.isEmpty) {
      String message;
      if (_selectedListId != null) {
        if ((_selectedListChannels ?? 0) == 0) {
          message = 'Esta lista no tiene canales asignados.';
        } else {
          message = 'No hay vídeos recientes para esta lista.';
        }
      } else {
        message = 'No hay vídeos recientes en tus suscripciones.';
      }
      return Center(
        child: Text(message),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadVideos(userInitiated: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _videos.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _ListsChipsRow(
              lists: _lists,
              hasAssignments: _hasAssignments,
              selectedListId: _selectedListId,
              onSelectList: _handleListTap,
              scrollController: _listsScrollController,
              chipKeys: _listChipKeys,
            );
          }
          final video = _videos[index - 1];
          return _VideoCard(
            video: video,
            channelAvatarUrl: _channelAvatars[video.channelId] ?? '',
            hasSummary: _summaryByVideoId[video.id] ?? false,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VideoDetailScreen(
                    video: video,
                    accessToken: _accessToken,
                    channelAvatarUrl: _channelAvatars[video.channelId] ?? '',
                    quotaTracker: widget.quotaTracker,
                    aiCostTracker: widget.aiCostTracker,
                  ),
                ),
              ).then((_) => _loadSummaryFlags(_videos));
            },
          );
        },
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
  });

  final YouTubeVideo video;
  final String channelAvatarUrl;
  final bool hasSummary;
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
                Column(
                  children: [
                    ChannelAvatar(
                      name: video.channelTitle,
                      imageUrl: channelAvatarUrl,
                    ),
                    const SizedBox(height: 6),
                    if (hasSummary)
                      const Icon(
                        Icons.check_circle,
                        color: Color(0xFFFA1021),
                        size: 16,
                      ),
                  ],
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

class _ListsChipsRow extends StatelessWidget {
  const _ListsChipsRow({
    required this.lists,
    required this.hasAssignments,
    required this.selectedListId,
    required this.onSelectList,
    required this.scrollController,
    required this.chipKeys,
  });

  final List<SubscriptionList> lists;
  final bool Function(String listId) hasAssignments;
  final String? selectedListId;
  final ValueChanged<String> onSelectList;
  final ScrollController scrollController;
  final Map<String, GlobalKey> chipKeys;

  @override
  Widget build(BuildContext context) {
    if (lists.isEmpty) {
      return const SizedBox(height: 0);
    }

    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        controller: scrollController,
        itemCount: lists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final list = lists[index];
          final active = hasAssignments(list.id);
          final selected = selectedListId == list.id;
          final labelColor = selected
              ? Colors.white
              : active
                  ? Colors.white70
                  : Colors.white38;
          return ChoiceChip(
            key: chipKeys[list.id],
            avatar: Icon(
              iconForListKey(list.iconKey),
              size: 18,
              color: labelColor,
            ),
            label: Text(list.name),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onSelectList(list.id),
            labelStyle: TextStyle(color: labelColor),
            backgroundColor:
                active ? const Color(0xFF1F1F1F) : const Color(0xFF141414),
            selectedColor: const Color(0xFFFA1021),
            side: BorderSide(
              color:
                  selected ? const Color(0xFFFA1021) : Colors.transparent,
            ),
          );
        },
      ),
    );
  }
}
