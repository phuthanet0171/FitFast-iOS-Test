import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/weight_entry.dart';

class WeightHistoryService {
  WeightHistoryService._();

  static final instance = WeightHistoryService._();
  static const _legacyKey = 'fitfast_weight_history_v1';
  static const _legacyOwnerKey = 'fitfast_weight_history_v1_owner';
  static const _userKeyPrefix = 'fitfast_weight_history_v2_';
  static const _migratedPrefix = 'fitfast_weight_history_migrated_';
  static const _dirtyPrefix = 'fitfast_weight_history_dirty_';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;
  String _userKey(String userId) => '$_userKeyPrefix$userId';

  Future<List<WeightEntry>> loadAll() async {
    final userId = _userId;
    if (userId == null) return _loadLocal(_legacyKey);

    final local = await _loadLocal(_userKey(userId));
    final dirty = await _preferences.getBool('$_dirtyPrefix$userId') ?? false;
    if (dirty) {
      try {
        await _replaceRemote(userId, local);
        await _preferences.setBool('$_dirtyPrefix$userId', false);
        await _preferences.setBool('$_migratedPrefix$userId', true);
        return local;
      } catch (_) {
        return local;
      }
    }

    try {
      final remote = await _loadRemote(userId);
      final migrated =
          await _preferences.getBool('$_migratedPrefix$userId') ?? false;
      if (migrated || remote.isNotEmpty) {
        await _writeLocal(_userKey(userId), remote);
        await _preferences.setBool('$_migratedPrefix$userId', true);
        return remote;
      }

      final migrationSource =
          local.isNotEmpty ? local : await _claimLegacyHistory(userId);
      if (migrationSource.isNotEmpty) {
        await _replaceRemote(userId, migrationSource);
        await _writeLocal(_userKey(userId), migrationSource);
      }
      await _preferences.setBool('$_migratedPrefix$userId', true);
      return migrationSource;
    } catch (_) {
      return local.isNotEmpty ? local : await _loadOwnedLegacyHistory(userId);
    }
  }

  Future<void> save(WeightEntry entry) async {
    final userId = _userId;
    final key = userId == null ? _legacyKey : _userKey(userId);
    final entries = userId == null ? await _loadLocal(key) : await loadAll();
    var index = entries.indexWhere((item) => item.id == entry.id);
    if (index < 0) {
      index = entries.indexWhere((item) => _sameDay(item.date, entry.date));
    }
    late final WeightEntry savedEntry;
    if (index >= 0) {
      savedEntry = WeightEntry(
        id: entries[index].id,
        date: entry.date,
        weight: entry.weight,
        note: entry.note,
      );
      entries[index] = savedEntry;
    } else {
      savedEntry = entry;
      entries.add(savedEntry);
    }
    _sort(entries);
    await _writeLocal(key, entries);
    if (userId == null) return;

    await _preferences.setBool('$_dirtyPrefix$userId', true);
    try {
      await _upsertRemote(userId, savedEntry);
      await _preferences.setBool('$_dirtyPrefix$userId', false);
      await _preferences.setBool('$_migratedPrefix$userId', true);
    } catch (_) {
      // The local change is retained and retried on the next load.
    }
  }

  Future<void> seedIfEmpty(double weight) async {
    if (weight <= 0 || (await loadAll()).isNotEmpty) return;
    final now = DateTime.now();
    await save(WeightEntry(
      id: 'initial_${now.microsecondsSinceEpoch}',
      date: DateTime(now.year, now.month, now.day),
      weight: weight,
      note: 'น้ำหนักเริ่มต้น',
    ));
  }

  /// Records [weight] for today when it differs from the latest entry, so a
  /// weight changed in the health profile also appears in the history.
  Future<void> recordToday(double weight) async {
    if (weight <= 0) return;
    final entries = await loadAll();
    if (entries.isEmpty) return seedIfEmpty(weight);
    if ((entries.last.weight - weight).abs() < .05) return;
    final now = DateTime.now();
    await save(WeightEntry(
      id: 'weight_${now.microsecondsSinceEpoch}',
      date: DateTime(now.year, now.month, now.day),
      weight: weight,
      note: '',
    ));
  }

  /// The most recent weight, or null when nothing has been logged.
  Future<double?> latestWeight() async {
    final entries = await loadAll();
    return entries.isEmpty ? null : entries.last.weight;
  }

  Future<void> delete(String id) async {
    final userId = _userId;
    final key = userId == null ? _legacyKey : _userKey(userId);
    final entries = userId == null ? await _loadLocal(key) : await loadAll();
    entries.removeWhere((entry) => entry.id == id);
    await _writeLocal(key, entries);
    if (userId == null) return;

    await _preferences.setBool('$_dirtyPrefix$userId', true);
    try {
      await Supabase.instance.client
          .from('weight_records')
          .delete()
          .eq('user_id', userId)
          .eq('id', id);
      await _preferences.setBool('$_dirtyPrefix$userId', false);
      await _preferences.setBool('$_migratedPrefix$userId', true);
    } catch (_) {
      // The complete local state will replace the remote state on retry.
    }
  }

  Future<void> clear() async {
    final userId = _userId;
    if (userId == null) {
      await _preferences.remove(_legacyKey);
      return;
    }
    await _preferences.remove(_userKey(userId));
    await _preferences.remove('$_dirtyPrefix$userId');
  }

  /// PostgREST returns at most 1,000 rows per request, so read in pages.
  static const _pageSize = 1000;

  Future<List<WeightEntry>> _loadRemote(String userId) async {
    final entries = <WeightEntry>[];
    for (var from = 0;; from += _pageSize) {
      final rows = await Supabase.instance.client
          .from('weight_records')
          .select('id, recorded_on, weight_kg, note')
          .eq('user_id', userId)
          .order('recorded_on', ascending: true)
          .range(from, from + _pageSize - 1);
      entries.addAll((rows as List).map((row) => WeightEntry(
            id: row['id'] as String,
            date: DateTime.parse(row['recorded_on'] as String),
            weight: (row['weight_kg'] as num).toDouble(),
            note: row['note'] as String? ?? '',
          )));
      if (rows.length < _pageSize) break;
    }
    // Callers rely on oldest-first order (the latest weight is last).
    _sort(entries);
    return entries;
  }

  Future<void> _upsertRemote(String userId, WeightEntry entry) async {
    await Supabase.instance.client.from('weight_records').upsert({
      'id': entry.id,
      'user_id': userId,
      'recorded_on': _dateKey(entry.date),
      'weight_kg': entry.weight,
      'note': entry.note,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,recorded_on');
  }

  Future<void> _replaceRemote(
    String userId,
    List<WeightEntry> entries,
  ) async {
    await Supabase.instance.client
        .from('weight_records')
        .delete()
        .eq('user_id', userId);
    if (entries.isEmpty) return;
    await Supabase.instance.client.from('weight_records').insert(
          entries
              .map((entry) => {
                    'id': entry.id,
                    'user_id': userId,
                    'recorded_on': _dateKey(entry.date),
                    'weight_kg': entry.weight,
                    'note': entry.note,
                  })
              .toList(),
        );
  }

  Future<List<WeightEntry>> _claimLegacyHistory(String userId) async {
    final owner = await _preferences.getString(_legacyOwnerKey);
    if (owner != null && owner != userId) return [];
    final entries = await _loadLocal(_legacyKey);
    if (entries.isNotEmpty) {
      await _preferences.setString(_legacyOwnerKey, userId);
    }
    return entries;
  }

  Future<List<WeightEntry>> _loadOwnedLegacyHistory(String userId) async {
    final owner = await _preferences.getString(_legacyOwnerKey);
    if (owner != null && owner != userId) return [];
    return _loadLocal(_legacyKey);
  }

  Future<List<WeightEntry>> _loadLocal(String key) async {
    final source = await _preferences.getString(key);
    if (source == null || source.isEmpty) return [];
    try {
      final decoded = jsonDecode(source) as List<dynamic>;
      final entries = decoded
          .map((item) => WeightEntry.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .where((entry) => entry.weight > 0)
          .toList();
      _sort(entries);
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeLocal(String key, List<WeightEntry> entries) =>
      _preferences.setString(
        key,
        jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      );

  bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  void _sort(List<WeightEntry> entries) =>
      entries.sort((a, b) => a.date.compareTo(b.date));
}
