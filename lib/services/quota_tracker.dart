import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../storage/app_database.dart';

const int kDefaultYouTubeDailyQuota =
    int.fromEnvironment('YOUTUBE_DAILY_QUOTA', defaultValue: 10000);

class QuotaTracker extends ChangeNotifier {
  QuotaTracker({required this.dailyLimit});

  final int dailyLimit;
  bool _loaded = false;
  int _used = 0;
  Map<String, int> _breakdown = {};
  String _dateKey = _todayKey();

  bool get isLoaded => _loaded;
  int get used => _used;
  Map<String, int> get breakdown => Map.unmodifiable(_breakdown);
  int get remaining {
    final value = dailyLimit - _used;
    if (value < 0) return 0;
    return value;
  }

  Future<void> load() async {
    if (_loaded) return;
    final today = _todayKey();
    await _loadFromDatabase(today);
    _dateKey = today;
    _loaded = true;
    notifyListeners();
  }

  Future<void> addUnits(int units, {String? label}) async {
    if (units <= 0) return;
    await _ensureLoaded();
    await _rolloverIfNeeded();
    _used += units;
    if (label != null && label.isNotEmpty) {
      _breakdown[label] = (_breakdown[label] ?? 0) + units;
    }
    await _save();
    notifyListeners();
  }

  Future<void> reset() async {
    await _ensureLoaded();
    _used = 0;
    _breakdown = {};
    _dateKey = _todayKey();
    await _save();
    notifyListeners();
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) {
      await load();
    }
  }

  Future<void> _rolloverIfNeeded() async {
    final today = _todayKey();
    if (_dateKey != today) {
      _dateKey = today;
      await _loadFromDatabase(today);
    }
  }

  Future<void> _save() async {
    final db = await AppDatabase.instance.open();
    await db.transaction((txn) async {
      await txn.insert(
        'youtube_quota_daily',
        {'date': _dateKey, 'used': _used},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'youtube_quota_breakdown',
        where: 'date = ?',
        whereArgs: [_dateKey],
      );
      for (final entry in _breakdown.entries) {
        await txn.insert(
          'youtube_quota_breakdown',
          {
            'date': _dateKey,
            'label': entry.key,
            'units': entry.value,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  static String _todayKey() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _loadFromDatabase(String date) async {
    final db = await AppDatabase.instance.open();
    final dailyRows = await db.query(
      'youtube_quota_daily',
      where: 'date = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (dailyRows.isNotEmpty) {
      _used = dailyRows.first['used'] as int? ?? 0;
    } else {
      _used = 0;
    }

    final breakdownRows = await db.query(
      'youtube_quota_breakdown',
      where: 'date = ?',
      whereArgs: [date],
    );
    final breakdown = <String, int>{};
    for (final row in breakdownRows) {
      final label = row['label'] as String?;
      final units = row['units'] as int?;
      if (label == null || units == null) continue;
      breakdown[label] = units;
    }
    _breakdown = breakdown;
  }
}
