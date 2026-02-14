import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/youtube_subscription.dart';
import '../services/youtube_api_service.dart';
import '../services/quota_tracker.dart';
import '../storage/subscription_lists_store.dart';
import '../ui/list_hierarchy.dart';
import '../ui/list_icons.dart';
import 'channel_videos_screen.dart';

class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key, required this.accessToken, this.quotaTracker, this.onRefreshToken, this.listsVersion});

  final String accessToken;
  final QuotaTracker? quotaTracker;
  final Future<String?> Function({bool interactive})? onRefreshToken;
  final ValueListenable<int>? listsVersion;

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  static const String _allListId = '_all';
  static const String _unassignedListId = '_unassigned';

  late YouTubeApiService _api;
  late String _accessToken;
  final SubscriptionListsStore _store = SubscriptionListsStore();

  bool _loading = true;
  String? _error;
  List<YouTubeSubscription> _subscriptions = const [];
  List<SubscriptionList> _lists = const [];
  Map<String, Set<String>> _assignments = {};
  String _selectedListId = _allListId;
  String _searchQuery = '';
  VoidCallback? _listsVersionListener;

  @override
  void initState() {
    super.initState();
    _accessToken = widget.accessToken;
    _api = YouTubeApiService(accessToken: _accessToken, quotaTracker: widget.quotaTracker);
    _load();
    _listsVersionListener = () {
      _reloadListsFromStore();
    };
    widget.listsVersion?.addListener(_listsVersionListener!);
  }

  @override
  void dispose() {
    if (_listsVersionListener != null) {
      widget.listsVersion?.removeListener(_listsVersionListener!);
    }
    _api.dispose();
    super.dispose();
  }

  Future<void> _reloadListsFromStore() async {
    try {
      final data = await _store.load();
      if (!mounted) return;
      setState(() {
        _lists = data.lists;
        _assignments = data.assignments;
        _selectedListId = _resolveSelectedListId(current: _selectedListId, lists: _lists, assignments: _assignments, subscriptions: _subscriptions);
      });
    } catch (_) {
      // No-op.
    }
  }

  Future<void> _refreshAccessToken({required bool interactive}) async {
    if (widget.onRefreshToken == null) return;
    final token = await widget.onRefreshToken!(interactive: interactive);
    if (!mounted || token == null || token.isEmpty) return;
    if (token == _accessToken) return;
    _api.dispose();
    _accessToken = token;
    _api = YouTubeApiService(accessToken: _accessToken, quotaTracker: widget.quotaTracker);
  }

  Future<void> _load({bool userInitiated = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _refreshAccessToken(interactive: userInitiated);
      final data = await _store.load();
      final subscriptions = await _api.fetchSubscriptions();
      if (!mounted) return;
      setState(() {
        _lists = data.lists;
        _assignments = data.assignments;
        _subscriptions = subscriptions;
        _loading = false;
        _selectedListId = _resolveSelectedListId(current: _selectedListId, lists: _lists, assignments: _assignments, subscriptions: _subscriptions);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las suscripciones.\n$error';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    await _store.save(_lists, _assignments);
  }

  bool _hasAssignments(String listId) {
    final channels = _assignments[listId];
    return channels != null && channels.isNotEmpty;
  }

  void _toggleAssignment(String listId, String channelId, bool assigned) {
    final current = _assignments[listId] ?? <String>{};
    if (assigned) {
      current.add(channelId);
    } else {
      current.remove(channelId);
    }
    setState(() {
      if (current.isEmpty) {
        _assignments.remove(listId);
      } else {
        _assignments = {..._assignments, listId: current};
      }
    });
    _save();
  }

  Set<String> _listsForChannel(String channelId) {
    final listIds = <String>{};
    for (final entry in _assignments.entries) {
      if (entry.value.contains(channelId)) {
        listIds.add(entry.key);
      }
    }
    return listIds;
  }

  String _resolveSelectedListId({required String current, required List<SubscriptionList> lists, required Map<String, Set<String>> assignments, required List<YouTubeSubscription> subscriptions}) {
    final subscriptionIds = subscriptions.map((subscription) => subscription.channelId).toSet();
    final assignedInSubscriptions = <String>{};
    for (final entry in assignments.entries) {
      for (final channelId in entry.value) {
        if (subscriptionIds.contains(channelId)) {
          assignedInSubscriptions.add(channelId);
        }
      }
    }
    final unassignedCount = subscriptions.length - assignedInSubscriptions.length;
    final hasUnassigned = unassignedCount > 0;

    if (current == _unassignedListId && !hasUnassigned) {
      return _allListId;
    }

    if (current != _allListId && current != _unassignedListId && !lists.any((list) => list.id == current)) {
      return _allListId;
    }

    return current;
  }

  void _handleListTap(String listId) {
    setState(() {
      _selectedListId = listId;
    });
  }

  Future<void> _openDeepenPrompt(List<YouTubeSubscription> channels) async {
    final buffer = StringBuffer('Actualmente estoy siguiendo a estos canales:\n');
    if (channels.isEmpty) {
      buffer.writeln('- (sin canales)');
    } else {
      for (final channel in channels) {
        final title = channel.title.trim();
        if (title.isEmpty) continue;
        buffer.writeln('- $title');
      }
    }
    buffer.write('\nEn base a esta lista, me gustaría que me sugirieras ');
    final uri = Uri.parse('https://chatgpt.com/?prompt=${Uri.encodeComponent(buffer.toString())}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el enlace.')));
    }
  }

  void _openAssignLists(YouTubeSubscription subscription) {
    final selected = _listsForChannel(subscription.channelId);
    final listById = {for (final list in _lists) list.id: list};
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(title: Text(subscription.title), subtitle: const Text('Asignar a listas')),
                    if (_lists.isEmpty)
                      const Padding(padding: EdgeInsets.all(24), child: Text('No hay listas. Crea una lista en Perfil para empezar.'))
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _lists.length,
                          itemBuilder: (context, index) {
                            final list = _lists[index];
                            return CheckboxListTile(
                              value: selected.contains(list.id),
                              title: Text(listDisplayName(list, listById)),
                              secondary: Icon(iconForListKey(list.iconKey)),
                              onChanged: (value) {
                                final checked = value ?? false;
                                setSheetState(() {
                                  if (checked) {
                                    selected.add(list.id);
                                  } else {
                                    selected.remove(list.id);
                                  }
                                });
                                _toggleAssignment(list.id, subscription.channelId, checked);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openChannelVideos(YouTubeSubscription subscription) {
    final channelId = subscription.channelId.trim();
    if (channelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontró el canal.')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChannelVideosScreen(accessToken: _accessToken, channelId: channelId, channelTitle: subscription.title, channelAvatarUrl: subscription.thumbnailUrl, quotaTracker: widget.quotaTracker),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    if (_subscriptions.isEmpty) {
      return const Center(child: Text('No hay suscripciones disponibles.'));
    }

    final listById = {for (final list in _lists) list.id: list};

    final assignedChannels = <String>{};
    final listCounts = <String, int>{};
    for (final entry in _assignments.entries) {
      assignedChannels.addAll(entry.value);
      listCounts[entry.key] = entry.value.length;
    }
    final assignedInSubscriptions = <String>{};
    final listCountsInSubscriptions = <String, int>{};
    for (final subscription in _subscriptions) {
      final listIds = _listsForChannel(subscription.channelId);
      if (listIds.isNotEmpty) {
        assignedInSubscriptions.add(subscription.channelId);
      }
      for (final listId in listIds) {
        listCountsInSubscriptions[listId] = (listCountsInSubscriptions[listId] ?? 0) + 1;
      }
    }

    final selectedAssignments = _selectedListId == _allListId || _selectedListId == _unassignedListId ? null : (_assignments[_selectedListId] ?? <String>{});
    final listFiltered = _selectedListId == _allListId
        ? _subscriptions
        : _selectedListId == _unassignedListId
        ? _subscriptions.where((subscription) => !assignedChannels.contains(subscription.channelId)).toList()
        : _subscriptions.where((subscription) => selectedAssignments!.contains(subscription.channelId)).toList();
    final query = _searchQuery.trim().toLowerCase();
    final filteredSubscriptions = query.isEmpty ? listFiltered : listFiltered.where((subscription) => subscription.title.toLowerCase().contains(query)).toList();
    final unassignedCount = _subscriptions.length - assignedInSubscriptions.length;
    final showEmptyState = filteredSubscriptions.isEmpty;
    final emptyMessage = query.isNotEmpty
        ? 'No hay canales que coincidan con la búsqueda.'
        : _selectedListId == _unassignedListId
        ? 'No hay canales sin lista.'
        : _selectedListId == _allListId
        ? 'No hay suscripciones disponibles.'
        : selectedAssignments != null && selectedAssignments.isEmpty
        ? 'Esta lista no tiene canales asignados.'
        : 'Ningún canal de esta lista está en tus suscripciones.';

    return RefreshIndicator(
      onRefresh: () => _load(userInitiated: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: showEmptyState ? 2 : filteredSubscriptions.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSpecificList = _selectedListId != _allListId && _selectedListId != _unassignedListId;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ListsChipsRow(
                  lists: _lists,
                  selectedListId: _selectedListId,
                  hasAssignments: _hasAssignments,
                  onSelectList: _handleListTap,
                  allListId: _allListId,
                  unassignedListId: _unassignedListId,
                  listCounts: listCountsInSubscriptions,
                  totalCount: _subscriptions.length,
                  unassignedCount: unassignedCount,
                  showUnassigned: unassignedCount > 0,
                  listById: listById,
                ),
                if (isSpecificList) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: listFiltered.isEmpty ? null : () => _openDeepenPrompt(listFiltered),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFA1021), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('Profundizar'),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar canales',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      suffixIcon: _searchQuery.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            );
          }
          if (showEmptyState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(emptyMessage)),
            );
          }
          final subscription = filteredSubscriptions[index - 1];
          final listIds = _listsForChannel(subscription.channelId);
          final listItems = _lists.where((list) => listIds.contains(list.id)).toList();
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: InkWell(
              onTap: () => _openChannelVideos(subscription),
              borderRadius: BorderRadius.circular(28),
              child: _SubscriptionThumbnail(url: subscription.thumbnailUrl),
            ),
            title: Text(subscription.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: listItems.isEmpty
                ? const Text('Sin listas asignadas')
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final list in listItems) Chip(avatar: Icon(iconForListKey(list.iconKey), size: 16), label: Text(listDisplayName(list, listById)), visualDensity: VisualDensity.compact)],
                  ),
            isThreeLine: listItems.isNotEmpty,
            onTap: () => _openAssignLists(subscription),
          );
        },
      ),
    );
  }
}

class _SubscriptionThumbnail extends StatelessWidget {
  const _SubscriptionThumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(color: Colors.black12, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Icon(Icons.account_circle),
      );
    }

    return ClipOval(child: Image.network(url, width: 56, height: 56, fit: BoxFit.cover));
  }
}

class _ListsChipsRow extends StatelessWidget {
  const _ListsChipsRow({
    required this.lists,
    required this.selectedListId,
    required this.hasAssignments,
    required this.onSelectList,
    required this.allListId,
    required this.unassignedListId,
    required this.listCounts,
    required this.totalCount,
    required this.unassignedCount,
    required this.showUnassigned,
    required this.listById,
  });

  final List<SubscriptionList> lists;
  final String selectedListId;
  final bool Function(String listId) hasAssignments;
  final ValueChanged<String> onSelectList;
  final String allListId;
  final String unassignedListId;
  final Map<String, int> listCounts;
  final int totalCount;
  final int unassignedCount;
  final bool showUnassigned;
  final Map<String, SubscriptionList> listById;

  @override
  Widget build(BuildContext context) {
    final totalChips = lists.length + (showUnassigned ? 1 : 0) + 1;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: totalChips,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            final selected = selectedListId == allListId;
            final labelColor = selected ? Colors.white : Colors.white70;
            final label = 'Todos ($totalCount)';
            return ChoiceChip(
              avatar: Icon(Icons.view_list, size: 18, color: labelColor),
              label: Text(label),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => onSelectList(allListId),
              labelStyle: TextStyle(color: labelColor),
              backgroundColor: const Color(0xFF141414),
              selectedColor: const Color(0xFFFA1021),
              side: BorderSide(color: selected ? const Color(0xFFFA1021) : Colors.transparent),
            );
          }

          if (showUnassigned && index == 1) {
            final selected = selectedListId == unassignedListId;
            final labelColor = selected ? Colors.white : Colors.white70;
            final label = 'Sin lista ($unassignedCount)';
            return ChoiceChip(
              avatar: Icon(Icons.remove_circle_outline, size: 18, color: labelColor),
              label: Text(label),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => onSelectList(unassignedListId),
              labelStyle: TextStyle(color: labelColor),
              backgroundColor: const Color(0xFF141414),
              selectedColor: const Color(0xFFFA1021),
              side: BorderSide(color: selected ? const Color(0xFFFA1021) : Colors.transparent),
            );
          }

          final listIndex = showUnassigned ? index - 2 : index - 1;
          final list = lists[listIndex];
          final active = hasAssignments(list.id);
          final selected = selectedListId == list.id;
          final labelColor = selected
              ? Colors.white
              : active
              ? Colors.white70
              : Colors.white38;
          final count = listCounts[list.id] ?? 0;
          final label = '${listDisplayName(list, listById)} ($count)';
          return ChoiceChip(
            avatar: Icon(iconForListKey(list.iconKey), size: 18, color: labelColor),
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onSelectList(list.id),
            labelStyle: TextStyle(color: labelColor),
            backgroundColor: active ? const Color(0xFF1F1F1F) : const Color(0xFF141414),
            selectedColor: const Color(0xFFFA1021),
            side: BorderSide(color: selected ? const Color(0xFFFA1021) : Colors.transparent),
          );
        },
      ),
    );
  }
}
