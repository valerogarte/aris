import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionList {
  SubscriptionList({
    required this.id,
    required this.name,
    required this.iconKey,
  });

  final String id;
  final String name;
  final String iconKey;

  SubscriptionList copyWith({String? name, String? iconKey}) {
    return SubscriptionList(
      id: id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconKey': iconKey,
      };

  factory SubscriptionList.fromJson(Map<String, dynamic> json) {
    return SubscriptionList(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      iconKey: (json['iconKey'] as String?) ?? 'label',
    );
  }
}

class SubscriptionListsData {
  SubscriptionListsData({
    required this.lists,
    required this.assignments,
  });

  final List<SubscriptionList> lists;
  final Map<String, Set<String>> assignments;
}

class SubscriptionListsStore {
  static const String _storageKey = 'subscription_lists_state';

  Future<SubscriptionListsData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return SubscriptionListsData(
        lists: const [],
        assignments: {},
      );
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final rawLists = (decoded['lists'] as List?) ?? const [];
    final lists = rawLists
        .whereType<Map<String, dynamic>>()
        .map(SubscriptionList.fromJson)
        .where((list) => list.id.isNotEmpty)
        .toList();

    final assignments = <String, Set<String>>{};
    final rawAssignments =
        (decoded['assignments'] as Map<String, dynamic>?) ?? {};
    rawAssignments.forEach((listId, value) {
      final ids = (value as List?)?.whereType<String>().toSet() ?? <String>{};
      assignments[listId] = ids;
    });

    return SubscriptionListsData(
      lists: lists,
      assignments: assignments,
    );
  }

  Future<void> save(
    List<SubscriptionList> lists,
    Map<String, Set<String>> assignments,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'lists': lists.map((list) => list.toJson()).toList(),
      'assignments': assignments.map(
        (key, value) => MapEntry(key, value.toList()),
      ),
    };
    await prefs.setString(_storageKey, jsonEncode(data));
  }
}
