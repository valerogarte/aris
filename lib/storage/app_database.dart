import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _dbName = 'aris.db';
  static const int _dbVersion = 1;
  static const String _table = 'kv';

  static const List<String> _migrateKeys = [
    'ai_provider_settings',
    'subscription_lists_state',
    'youtube_quota_state',
    'ai_cost_state',
    'ai_cost_history',
    'sftp_settings',
  ];

  static const List<String> _migratePrefixes = [
    'expiring_cache:',
  ];

  Database? _db;
  bool _migrationChecked = false;

  Future<String> databasePath() async {
    final dbPath = await getDatabasesPath();
    return p.join(dbPath, _dbName);
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    _migrationChecked = false;
  }

  Future<void> checkpoint() async {
    final db = await _openDb();
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Best-effort: if checkpoint fails, continue with export.
    }
  }

  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    final path = await databasePath();
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE $_table (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
    );
    await _migrateFromSharedPreferencesIfNeeded(_db!);
    return _db!;
  }

  Future<void> _migrateFromSharedPreferencesIfNeeded(Database db) async {
    if (_migrationChecked) return;
    _migrationChecked = true;
    final existingRows = await db.query(_table, columns: const ['key']);
    final existingKeys = existingRows
        .map((row) => row['key'] as String)
        .toSet();

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final batch = db.batch();
    final migratedKeys = <String>[];

    for (final key in keys) {
      if (!_shouldMigrateKey(key)) continue;
      if (existingKeys.contains(key)) continue;
      final value = prefs.get(key);
      final serialized = _serializeValue(value);
      if (serialized == null) continue;
      batch.insert(
        _table,
        {'key': key, 'value': serialized},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      migratedKeys.add(key);
    }

    if (migratedKeys.isNotEmpty) {
      await batch.commit(noResult: true);
      for (final key in migratedKeys) {
        await prefs.remove(key);
      }
    }
  }

  bool _shouldMigrateKey(String key) {
    if (_migrateKeys.contains(key)) return true;
    for (final prefix in _migratePrefixes) {
      if (key.startsWith(prefix)) return true;
    }
    return false;
  }

  String? _serializeValue(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is int ||
        value is double ||
        value is bool ||
        value is List<String> ||
        value is Map ||
        value is List) {
      return jsonEncode(value);
    }
    return value.toString();
  }

  Future<String?> getString(String key) async {
    final db = await _openDb();
    final rows = await db.query(
      _table,
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setString(String key, String value) async {
    final db = await _openDb();
    await db.insert(
      _table,
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String key) async {
    final db = await _openDb();
    await db.delete(_table, where: 'key = ?', whereArgs: [key]);
  }

  Future<List<String>> keys() async {
    final db = await _openDb();
    final rows = await db.query(_table, columns: const ['key']);
    return rows.map((row) => row['key'] as String).toList();
  }

  Future<Map<String, String>> getAllKeyValues({
    List<String>? prefixes,
    List<String>? exactKeys,
  }) async {
    final db = await _openDb();
    if ((prefixes == null || prefixes.isEmpty) &&
        (exactKeys == null || exactKeys.isEmpty)) {
      final rows = await db.query(_table);
      return {
        for (final row in rows)
          row['key'] as String: row['value'] as String,
      };
    }

    final where = <String>[];
    final args = <Object?>[];
    if (exactKeys != null && exactKeys.isNotEmpty) {
      where.add('key IN (${List.filled(exactKeys.length, '?').join(',')})');
      args.addAll(exactKeys);
    }
    if (prefixes != null && prefixes.isNotEmpty) {
      where.add(
        prefixes.map((_) => 'key LIKE ?').join(' OR '),
      );
      for (final prefix in prefixes) {
        args.add('$prefix%');
      }
    }
    final rows = await db.query(
      _table,
      where: where.join(' OR '),
      whereArgs: args,
    );
    return {
      for (final row in rows)
        row['key'] as String: row['value'] as String,
    };
  }

  Future<void> removeMany(Iterable<String> keys) async {
    final db = await _openDb();
    final list = keys.toList();
    if (list.isEmpty) return;
    await db.delete(
      _table,
      where: 'key IN (${List.filled(list.length, '?').join(',')})',
      whereArgs: list,
    );
  }
}
