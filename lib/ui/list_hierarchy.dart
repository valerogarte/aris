import '../storage/subscription_lists_store.dart';

String listDisplayName(
  SubscriptionList list,
  Map<String, SubscriptionList> byId, {
  String separator = ' / ',
}) {
  final parts = <String>[];
  final visited = <String>{};
  SubscriptionList? current = list;
  while (current != null &&
      current.id.isNotEmpty &&
      !visited.contains(current.id)) {
    visited.add(current.id);
    final name = current.name.trim();
    if (name.isNotEmpty) {
      parts.add(name);
    }
    final parentId = current.parentId.trim();
    if (parentId.isEmpty) break;
    current = byId[parentId];
  }
  if (parts.isEmpty) return list.name;
  return parts.reversed.join(separator);
}
