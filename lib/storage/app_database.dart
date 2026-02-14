import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _dbName = 'aris.db';
  static const int _dbVersion = 3;
  static const String _table = 'kv';
  static const String _tableAiCostDaily = 'ai_cost_daily';
  static const String _tableAiCostBreakdown = 'ai_cost_breakdown';
  static const String _tableQuotaDaily = 'youtube_quota_daily';
  static const String _tableQuotaBreakdown = 'youtube_quota_breakdown';
  static const String _tableChannels = 'channels';
  static const String _tableHistory = 'history_videos';

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
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSchema(db);
        } else if (oldVersion < 3) {
          await _createSchema(db);
        }
      },
    );
    await _migrateFromSharedPreferencesIfNeeded(_db!);
    await _migrateKvToStructuredTablesIfNeeded(_db!);
    return _db!;
  }

  Future<Database> open() async {
    return _openDb();
  }

  Future<void> _createSchema(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $_table (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $_tableAiCostDaily ('
      'date TEXT PRIMARY KEY, '
      'micro_cost INTEGER NOT NULL'
      ')',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $_tableAiCostBreakdown ('
      'date TEXT NOT NULL, '
      'label TEXT NOT NULL, '
      'micro_cost INTEGER NOT NULL, '
      'PRIMARY KEY(date, label)'
      ')',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_cost_breakdown_date '
      'ON $_tableAiCostBreakdown(date)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $_tableQuotaDaily ('
      'date TEXT PRIMARY KEY, '
      'used INTEGER NOT NULL'
      ')',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $_tableQuotaBreakdown ('
      'date TEXT NOT NULL, '
      'label TEXT NOT NULL, '
      'units INTEGER NOT NULL, '
      'PRIMARY KEY(date, label)'
      ')',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_quota_breakdown_date '
      'ON $_tableQuotaBreakdown(date)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $_tableChannels ('
      'channel_id TEXT PRIMARY KEY, '
      'title TEXT NOT NULL, '
      'description TEXT, '
      'thumbnail_url TEXT, '
      'published_at TEXT, '
      'custom_url TEXT, '
      'country TEXT, '
      'uploads_playlist_id TEXT, '
      'subscriber_count INTEGER, '
      'view_count INTEGER, '
      'video_count INTEGER, '
      'raw_json TEXT, '
      'updated_at INTEGER NOT NULL'
      ')',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $_tableHistory ('
      'video_id TEXT PRIMARY KEY, '
      'title TEXT NOT NULL, '
      'channel_id TEXT, '
      'channel_title TEXT, '
      'thumbnail_url TEXT, '
      'published_at TEXT, '
      'duration_seconds INTEGER, '
      'watched_at INTEGER, '
      'summary_requested_at INTEGER, '
      'last_activity_at INTEGER NOT NULL'
      ')',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_history_activity '
      'ON $_tableHistory(last_activity_at)',
    );
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

  Future<void> _migrateKvToStructuredTablesIfNeeded(Database db) async {
    final rows = await db.query(
      _table,
      columns: const ['key', 'value'],
      where: 'key IN (?, ?, ?)',
      whereArgs: const [
        'ai_cost_state',
        'ai_cost_history',
        'youtube_quota_state',
      ],
    );
    if (rows.isEmpty) return;

    String? costState;
    String? costHistory;
    String? quotaState;
    for (final row in rows) {
      final key = row['key'] as String?;
      final value = row['value'] as String?;
      if (key == 'ai_cost_state') costState = value;
      if (key == 'ai_cost_history') costHistory = value;
      if (key == 'youtube_quota_state') quotaState = value;
    }

    final batch = db.batch();

    if (costState != null && costState.isNotEmpty) {
      _insertAiCostFromJson(batch, costState);
      batch.delete(_table, where: 'key = ?', whereArgs: ['ai_cost_state']);
    }

    if (costHistory != null && costHistory.isNotEmpty) {
      _insertAiCostHistoryFromJson(batch, costHistory);
      batch.delete(_table, where: 'key = ?', whereArgs: ['ai_cost_history']);
    }

    if (quotaState != null && quotaState.isNotEmpty) {
      _insertQuotaFromJson(batch, quotaState);
      batch.delete(_table, where: 'key = ?', whereArgs: ['youtube_quota_state']);
    }

    await batch.commit(noResult: true);
  }

  void _insertAiCostFromJson(Batch batch, String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final date = (decoded['date'] as String?) ?? '';
      if (date.isEmpty) return;
      final microCost = (decoded['microCost'] as num?)?.toInt() ?? 0;
      batch.insert(
        _tableAiCostDaily,
        {'date': date, 'micro_cost': microCost},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.delete(
        _tableAiCostBreakdown,
        where: 'date = ?',
        whereArgs: [date],
      );
      final breakdown =
          (decoded['breakdown'] as Map<String, dynamic>?) ?? {};
      for (final entry in breakdown.entries) {
        final value = (entry.value as num?)?.toInt() ?? 0;
        batch.insert(
          _tableAiCostBreakdown,
          {
            'date': date,
            'label': entry.key,
            'micro_cost': value,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (_) {}
  }

  void _insertAiCostHistoryFromJson(Batch batch, String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final date = entry.key;
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        final microCost = (value['microCost'] as num?)?.toInt() ?? 0;
        batch.insert(
          _tableAiCostDaily,
          {'date': date, 'micro_cost': microCost},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        batch.delete(
          _tableAiCostBreakdown,
          where: 'date = ?',
          whereArgs: [date],
        );
        final breakdown =
            (value['breakdown'] as Map<String, dynamic>?) ?? {};
        for (final breakdownEntry in breakdown.entries) {
          final amount = (breakdownEntry.value as num?)?.toInt() ?? 0;
          batch.insert(
            _tableAiCostBreakdown,
            {
              'date': date,
              'label': breakdownEntry.key,
              'micro_cost': amount,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    } catch (_) {}
  }

  void _insertQuotaFromJson(Batch batch, String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final date = (decoded['date'] as String?) ?? '';
      if (date.isEmpty) return;
      final used = (decoded['used'] as num?)?.toInt() ?? 0;
      batch.insert(
        _tableQuotaDaily,
        {'date': date, 'used': used},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.delete(
        _tableQuotaBreakdown,
        where: 'date = ?',
        whereArgs: [date],
      );
      final breakdown =
          (decoded['breakdown'] as Map<String, dynamic>?) ?? {};
      for (final entry in breakdown.entries) {
        final units = (entry.value as num?)?.toInt() ?? 0;
        batch.insert(
          _tableQuotaBreakdown,
          {
            'date': date,
            'label': entry.key,
            'units': units,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (_) {}
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
