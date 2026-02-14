import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../storage/app_database.dart';

class AiCostTracker extends ChangeNotifier {
  AiCostTracker({this.currencySymbol = '€'});

  static const int _maxHistoryDays = 90;

  final String currencySymbol;
  bool _loaded = false;
  int _microCost = 0;
  Map<String, int> _breakdown = {};
  String _dateKey = _todayKey();
  Map<String, _DailyCost> _history = {};

  bool get isLoaded => _loaded;
  double get totalCost => _microCost / 1000000.0;
  int get microCost => _microCost;
  Map<String, int> get breakdown => Map.unmodifiable(_breakdown);
  String get currentDateKey => _dateKey;

  String get formattedTotal {
    return '$currencySymbol${totalCost.toStringAsFixed(2)}';
  }

  Future<void> load() async {
    if (_loaded) return;
    final today = _todayKey();
    await _loadFromDatabase(today);
    _dateKey = today;
    _loaded = true;
    await _pruneHistory();
    notifyListeners();
  }

  Future<void> addCostMicro(int microCost, {String? label}) async {
    if (microCost <= 0) return;
    await _ensureLoaded();
    await _rolloverIfNeeded();
    _microCost += microCost;
    if (label != null && label.isNotEmpty) {
      _breakdown[label] = (_breakdown[label] ?? 0) + microCost;
    }
    await _save();
    notifyListeners();
  }

  Future<void> reset() async {
    await _ensureLoaded();
    _microCost = 0;
    _breakdown = {};
    _dateKey = _todayKey();
    await _save();
    notifyListeners();
  }

  double totalFor(String dateKey) {
    final data = _getDailyCost(dateKey);
    if (data == null) return 0;
    return data.microCost / 1000000.0;
  }

  Map<String, int> breakdownFor(String dateKey) {
    final data = _getDailyCost(dateKey);
    if (data == null) return {};
    return Map.unmodifiable(data.breakdown);
  }

  bool hasDataFor(String dateKey) {
    final data = _getDailyCost(dateKey);
    return data != null && data.microCost > 0;
  }

  List<String> historyDates() {
    final dates = _history.keys.toList()..sort();
    if (!_history.containsKey(_dateKey)) {
      dates.add(_dateKey);
    }
    return dates;
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
        'ai_cost_daily',
        {'date': _dateKey, 'micro_cost': _microCost},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'ai_cost_breakdown',
        where: 'date = ?',
        whereArgs: [_dateKey],
      );
      for (final entry in _breakdown.entries) {
        await txn.insert(
          'ai_cost_breakdown',
          {
            'date': _dateKey,
            'label': entry.key,
            'micro_cost': entry.value,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    _storeHistoryEntry(_dateKey, _microCost, _breakdown);
    await _pruneHistory();
  }

  static String _todayKey() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  _DailyCost? _getDailyCost(String dateKey) {
    if (dateKey == _dateKey) {
      return _DailyCost(
        microCost: _microCost,
        breakdown: Map<String, int>.from(_breakdown),
      );
    }
    return _history[dateKey];
  }

  void _storeHistoryEntry(
    String dateKey,
    int microCost,
    Map<String, int> breakdown,
  ) {
    _history[dateKey] = _DailyCost(
      microCost: microCost,
      breakdown: Map<String, int>.from(breakdown),
    );
  }

  Future<void> _loadFromDatabase(String today) async {
    final db = await AppDatabase.instance.open();
    final dailyRows = await db.query('ai_cost_daily');
    final breakdownRows = await db.query('ai_cost_breakdown');

    final breakdownByDate = <String, Map<String, int>>{};
    for (final row in breakdownRows) {
      final date = row['date'] as String?;
      final label = row['label'] as String?;
      final value = row['micro_cost'] as int?;
      if (date == null || label == null || value == null) continue;
      final map = breakdownByDate.putIfAbsent(date, () => {});
      map[label] = value;
    }

    final history = <String, _DailyCost>{};
    for (final row in dailyRows) {
      final date = row['date'] as String?;
      if (date == null || date.isEmpty) continue;
      final microCost = row['micro_cost'] as int? ?? 0;
      final breakdown = breakdownByDate[date] ?? {};
      history[date] = _DailyCost(
        microCost: microCost,
        breakdown: Map<String, int>.from(breakdown),
      );
    }

    _history = history;
    final todayData = _history[today];
    if (todayData != null) {
      _microCost = todayData.microCost;
      _breakdown = Map<String, int>.from(todayData.breakdown);
    } else {
      _microCost = 0;
      _breakdown = {};
    }
  }

  Future<void> _pruneHistory() async {
    if (_history.length <= _maxHistoryDays) return;
    final keys = _history.keys.toList()..sort();
    final removeCount = keys.length - _maxHistoryDays;
    if (removeCount <= 0) return;
    final toRemove = keys.take(removeCount).toList();
    for (final key in toRemove) {
      _history.remove(key);
    }
    final db = await AppDatabase.instance.open();
    for (final date in toRemove) {
      await db.delete(
        'ai_cost_breakdown',
        where: 'date = ?',
        whereArgs: [date],
      );
      await db.delete(
        'ai_cost_daily',
        where: 'date = ?',
        whereArgs: [date],
      );
    }
  }
}

class _DailyCost {
  _DailyCost({
    required this.microCost,
    required this.breakdown,
  });

  final int microCost;
  final Map<String, int> breakdown;
}
