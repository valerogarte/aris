import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../storage/app_database.dart';

const int kDefaultYouTubeDailyQuota =
    int.fromEnvironment('YOUTUBE_DAILY_QUOTA', defaultValue: 10000);

class QuotaTracker extends ChangeNotifier {
  QuotaTracker({required this.dailyLimit});

  static const String _storageKey = 'youtube_quota_state';

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
    final raw = await AppDatabase.instance.getString(_storageKey);
    final today = _todayKey();

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final storedDate = (decoded['date'] as String?) ?? today;
        final storedUsed = (decoded['used'] as num?)?.toInt() ?? 0;
        final storedBreakdown =
            decoded['breakdown'] as Map<String, dynamic>? ?? {};
        if (storedDate == today) {
          _used = storedUsed;
          _breakdown = storedBreakdown.map(
            (key, value) => MapEntry(
              key,
              (value as num?)?.toInt() ?? 0,
            ),
          );
        } else {
          _used = 0;
          _breakdown = {};
        }
      } catch (_) {
        _used = 0;
        _breakdown = {};
      }
    }

    _dateKey = today;
    _loaded = true;
    notifyListeners();
  }

  Future<void> addUnits(int units, {String? label}) async {
    if (units <= 0) return;
    await _ensureLoaded();
    _rolloverIfNeeded();
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

  void _rolloverIfNeeded() {
    final today = _todayKey();
    if (_dateKey != today) {
      _dateKey = today;
      _used = 0;
      _breakdown = {};
    }
  }

  Future<void> _save() async {
    final data = {
      'date': _dateKey,
      'used': _used,
      'breakdown': _breakdown,
    };
    await AppDatabase.instance.setString(_storageKey, jsonEncode(data));
  }

  static String _todayKey() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
