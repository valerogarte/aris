import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../storage/subscription_lists_store.dart';
import '../ui/list_hierarchy.dart';
import '../ui/list_icons.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    this.listsVersion,
  });

  final ValueListenable<int>? listsVersion;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final SubscriptionListsStore _store = SubscriptionListsStore();

  bool _loading = true;
  List<SubscriptionList> _lists = const [];
  Map<String, Set<String>> _assignments = {};
  VoidCallback? _listsVersionListener;

  @override
  void initState() {
    super.initState();
    _loadLists();
    _listsVersionListener = () {
      _loadLists();
    };
    widget.listsVersion?.addListener(_listsVersionListener!);
  }

  @override
  void dispose() {
    if (_listsVersionListener != null) {
      widget.listsVersion?.removeListener(_listsVersionListener!);
    }
    super.dispose();
  }

  Future<void> _loadLists() async {
    setState(() {
      _loading = true;
    });
    try {
      final data = await _store.load();
      if (!mounted) return;
      setState(() {
        _lists = data.lists;
        _assignments = data.assignments;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lists = const [];
        _assignments = {};
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_lists.isEmpty) {
      return const Center(
        child: Text('No hay etiquetas creadas.'),
      );
    }

    final listById = {
      for (final list in _lists) list.id: list,
    };

    return RefreshIndicator(
      onRefresh: _loadLists,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _lists.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final list = _lists[index];
          final displayName = listDisplayName(list, listById);
          final count = _assignments[list.id]?.length ?? 0;
          return ListTile(
            leading: Icon(iconForListKey(list.iconKey)),
            title: Text(displayName),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1F1F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          );
        },
      ),
    );
  }
}
