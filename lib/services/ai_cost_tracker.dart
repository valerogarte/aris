import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../storage/app_database.dart';

class AiCostTracker extends ChangeNotifier {
  AiCostTracker({this.currencySymbol = '€'});

  static const String _storageKey = 'ai_cost_state';
  static const String _historyKey = 'ai_cost_history';
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
    final raw = await AppDatabase.instance.getString(_storageKey);
    final historyRaw = await AppDatabase.instance.getString(_historyKey);
    final today = _todayKey();

    _history = _decodeHistory(historyRaw);

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final storedDate = (decoded['date'] as String?) ?? today;
        final storedCost = (decoded['microCost'] as num?)?.toInt() ?? 0;
        final storedBreakdown =
            decoded['breakdown'] as Map<String, dynamic>? ?? {};
        if (storedDate == today) {
          _microCost = storedCost;
          _breakdown = storedBreakdown.map(
            (key, value) => MapEntry(
              key,
              (value as num?)?.toInt() ?? 0,
            ),
          );
        } else {
          _storeHistoryEntry(
            storedDate,
            storedCost,
            storedBreakdown.map(
              (key, value) => MapEntry(
                key,
                (value as num?)?.toInt() ?? 0,
              ),
            ),
          );
          _microCost = 0;
          _breakdown = {};
        }
      } catch (_) {
        _microCost = 0;
        _breakdown = {};
      }
    }

    _dateKey = today;
    _loaded = true;
    _pruneHistory();
    await _save();
    notifyListeners();
  }

  Future<void> addCostMicro(int microCost, {String? label}) async {
    if (microCost <= 0) return;
    await _ensureLoaded();
    _rolloverIfNeeded();
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

  void _rolloverIfNeeded() {
    final today = _todayKey();
    if (_dateKey != today) {
      if (_microCost > 0 || _breakdown.isNotEmpty) {
        _storeHistoryEntry(_dateKey, _microCost, _breakdown);
      }
      _dateKey = today;
      _microCost = 0;
      _breakdown = {};
    }
  }

  Future<void> _save() async {
    final data = {
      'date': _dateKey,
      'microCost': _microCost,
      'breakdown': _breakdown,
    };
    await AppDatabase.instance.setString(
      _storageKey,
      jsonEncode(data),
    );
    await AppDatabase.instance.setString(
      _historyKey,
      jsonEncode(_encodeHistory()),
    );
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

  Map<String, _DailyCost> _decodeHistory(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, _DailyCost>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          final microCost = (value['microCost'] as num?)?.toInt() ?? 0;
          final breakdownRaw =
              value['breakdown'] as Map<String, dynamic>? ?? {};
          final breakdown = breakdownRaw.map(
            (key, val) => MapEntry(key, (val as num?)?.toInt() ?? 0),
          );
          result[entry.key] = _DailyCost(
            microCost: microCost,
            breakdown: breakdown,
          );
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> _encodeHistory() {
    return _history.map(
      (key, value) => MapEntry(
        key,
        {
          'microCost': value.microCost,
          'breakdown': value.breakdown,
        },
      ),
    );
  }

  void _pruneHistory() {
    if (_history.length <= _maxHistoryDays) return;
    final keys = _history.keys.toList()..sort();
    final removeCount = keys.length - _maxHistoryDays;
    for (var i = 0; i < removeCount; i += 1) {
      _history.remove(keys[i]);
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
