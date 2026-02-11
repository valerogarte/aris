import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ExpiringCacheStore {
  ExpiringCacheStore(this.namespace);

  final String namespace;

  static const String _prefix = 'expiring_cache';

  Future<String?> get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_fullKey(key));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final value = decoded['value'] as String?;
      final expiresAt = (decoded['expiresAt'] as num?)?.toInt();
      if (value == null || expiresAt == null) {
        await prefs.remove(_fullKey(key));
        return null;
      }
      if (DateTime.now().millisecondsSinceEpoch >= expiresAt) {
        await prefs.remove(_fullKey(key));
        return null;
      }
      return value;
    } catch (_) {
      await prefs.remove(_fullKey(key));
      return null;
    }
  }

  Future<void> set(String key, String value, Duration ttl) async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt =
        DateTime.now().add(ttl).millisecondsSinceEpoch;
    final data = {
      'value': value,
      'expiresAt': expiresAt,
    };
    await prefs.setString(_fullKey(key), jsonEncode(data));
  }

  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fullKey(key));
  }

  String _fullKey(String key) => '$_prefix:$namespace:$key';
}

String stableHash(String input) {
  const int fnvPrime = 0x01000193;
  int hash = 0x811c9dc5;
  for (final codeUnit in input.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * fnvPrime) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
