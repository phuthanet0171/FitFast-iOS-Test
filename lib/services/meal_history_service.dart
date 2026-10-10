import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/meal_entry.dart';

/// A food the user logs often, with the latest entry as its portion template.
class FrequentFood {
  const FrequentFood({required this.template, required this.count});

  final MealEntry template;
  final int count;
}

class MealHistoryService {
  MealHistoryService._();

  static final instance = MealHistoryService._();
  static const _legacyKey = 'fitfast_meal_entries_v1';
  static const _legacyOwnerKey = 'fitfast_meal_entries_v1_owner';
  static const _userKeyPrefix = 'fitfast_meal_entries_v2_';
  static const _migratedPrefix = 'fitfast_meal_entries_migrated_';
  // Set by the previous snapshot-based sync. Still honoured so an unsynced
  // snapshot on an upgraded device is not lost.
  static const _dirtyPrefix = 'fitfast_meal_entries_dirty_';
  static const _pendingPrefix = 'fitfast_meal_entries_pending_';
  static const _cacheLifetime = Duration(minutes: 5);
  static const _retryAfterFailure = Duration(seconds: 30);
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  String? _cacheUserId;
  List<MealEntry>? _cache;
  DateTime? _fetchedAt;
  DateTime? _failedAt;
  Future<void>? _busy;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;
  String _userKey(String userId) => '$_userKeyPrefix$userId';

  /// Runs storage operations one at a time so a sync never interleaves with
  /// another write and drops a pending change.
  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _busy;
    final done = Completer<void>();
    _busy = done.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      if (identical(_busy, done.future)) _busy = null;
      done.complete();
    }
  }

  Future<List<MealEntry>> loadDate(String dateKey, {bool refresh = false}) =>
      _serial(() async {
        final entries = await _readAll(refresh: refresh);
        return entries.where((entry) => entry.dateKey == dateKey).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });

  Future<MealEntry?> loadLatestDetailedForFood(int foodId) => _serial(() async {
        final entries = await _readAll();
        final matches = entries
            .where((entry) => entry.foodId == foodId && entry.isDetailed)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return matches.isEmpty ? null : matches.first;
      });

  /// Foods logged in the last [days] days, most used first. Foods eaten at
  /// [mealType] rank ahead of foods eaten at other meals.
  Future<List<FrequentFood>> loadFrequentFoods({
    MealType? mealType,
    int limit = 6,
    int days = 60,
  }) =>
      _serial(() async {
        final since = DateTime.now().subtract(Duration(days: days));
        final groups = <int, List<MealEntry>>{};
        for (final entry in await _readAll()) {
          if (entry.foodId <= 0 || entry.createdAt.isBefore(since)) continue;
          groups.putIfAbsent(entry.foodId, () => []).add(entry);
        }
        int mealCount(List<MealEntry> items) =>
            items.where((entry) => entry.mealType == mealType).length;
        MealEntry latest(List<MealEntry> items) {
          final preferred = items.where((e) => e.mealType == mealType);
          final pool = preferred.isEmpty ? items : preferred;
          return pool
              .reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
        }

        final ranked = groups.values.toList()
          ..sort((a, b) {
            final byMeal = mealCount(b).compareTo(mealCount(a));
            if (byMeal != 0) return byMeal;
            final byCount = b.length.compareTo(a.length);
            if (byCount != 0) return byCount;
            return latest(b).createdAt.compareTo(latest(a).createdAt);
          });
        return ranked
            .take(limit)
            .map((items) =>
                FrequentFood(template: latest(items), count: items.length))
            .toList();
      });

  Future<void> add(MealEntry entry) => addAll([entry]);

  Future<void> addAll(List<MealEntry> newEntries) => _serial(() async {
        if (newEntries.isEmpty) return;
        final entries = await _readAll();
        for (final entry in newEntries) {
          final index = entries.indexWhere((item) => item.id == entry.id);
          index >= 0 ? entries[index] = entry : entries.add(entry);
        }
        await _commit(entries, upserted: newEntries.map((entry) => entry.id));
      });

  Future<void> update(MealEntry entry) => _serial(() async {
        final entries = await _readAll();
        final index = entries.indexWhere((item) => item.id == entry.id);
        if (index < 0) return;
        entries[index] = entry;
        await _commit(entries, upserted: [entry.id]);
      });

  Future<void> delete(MealEntry entry) => _serial(() async {
        final entries = await _readAll();
        final before = entries.length;
        entries.removeWhere((item) => item.id == entry.id);
        if (entries.length == before) return;
        await _commit(entries, deleted: [entry.id]);
      });

  Future<void> clear() => _serial(() async {
        _resetCache();
        final userId = _userId;
        if (userId == null) {
          await _preferences.remove(_legacyKey);
          return;
        }
        await _preferences.remove(_userKey(userId));
        await _preferences.remove('$_dirtyPrefix$userId');
        await _preferences.remove('$_pendingPrefix$userId');
      });

  void _resetCache() {
    _cacheUserId = null;
    _cache = null;
    _fetchedAt = null;
    _failedAt = null;
  }

  /// Returns a mutable copy of the user's history. The cloud is read at most
  /// once per [_cacheLifetime] unless [refresh] is set.
  Future<List<MealEntry>> _readAll({bool refresh = false}) async {
    final userId = _userId;
    if (userId == null) return _loadLocal(_legacyKey);
    if (_cacheUserId != userId) _resetCache();

    final now = DateTime.now();
    final fresh =
        _fetchedAt != null && now.difference(_fetchedAt!) < _cacheLifetime;
    final recentlyFailed =
        _failedAt != null && now.difference(_failedAt!) < _retryAfterFailure;
    if (_cache != null && !refresh && (fresh || recentlyFailed)) {
      return List.of(_cache!);
    }

    final entries = await _fetch(userId);
    _cacheUserId = userId;
    _cache = entries;
    return List.of(entries);
  }

  Future<List<MealEntry>> _fetch(String userId) async {
    final key = _userKey(userId);
    final local = await _loadLocal(key);
    try {
      // Local changes must reach the cloud before the cloud copy replaces them.
      await _flushPending(userId, local);
      final remote = await _loadRemote(userId);
      final migrated =
          await _preferences.getBool('$_migratedPrefix$userId') ?? false;
      _fetchedAt = DateTime.now();
      _failedAt = null;
      if (migrated || remote.isNotEmpty) {
        await _writeLocal(key, remote);
        await _preferences.setBool('$_migratedPrefix$userId', true);
        return remote;
      }

      final source =
          local.isNotEmpty ? local : await _claimLegacyHistory(userId);
      if (source.isNotEmpty) {
        await _upsertRemote(userId, source);
        await _writeLocal(key, source);
      }
      await _preferences.setBool('$_migratedPrefix$userId', true);
      return source;
    } catch (_) {
      _failedAt = DateTime.now();
      return local.isNotEmpty ? local : await _loadOwnedLegacyHistory(userId);
    }
  }

  Future<void> _commit(
    List<MealEntry> entries, {
    Iterable<String> upserted = const [],
    Iterable<String> deleted = const [],
  }) async {
    _sort(entries);
    final userId = _userId;
    if (userId == null) {
      await _writeLocal(_legacyKey, entries);
      return;
    }

    await _writeLocal(_userKey(userId), entries);
    _cacheUserId = userId;
    _cache = List.of(entries);
    await _queuePending(userId, upserted: upserted, deleted: deleted);
    // The local write is done; the screen does not wait for the upload.
    unawaited(_serial(() => _pushPending(userId)));
  }

  Future<void> _pushPending(String userId) async {
    if (_userId != userId) return;
    try {
      await _flushPending(userId, _cache ?? await _loadLocal(_userKey(userId)));
    } catch (_) {
      // The change stays in the pending queue and is retried on the next read.
    }
  }

  Future<void> _flushPending(String userId, List<MealEntry> local) async {
    final legacyDirty =
        await _preferences.getBool('$_dirtyPrefix$userId') ?? false;
    if (legacyDirty) {
      await _replaceRemote(userId, local);
      await _preferences.setBool('$_dirtyPrefix$userId', false);
      await _preferences.remove('$_pendingPrefix$userId');
      await _preferences.setBool('$_migratedPrefix$userId', true);
      return;
    }

    final pending = await _loadPending(userId);
    if (pending.isEmpty) return;
    final byId = {for (final entry in local) entry.id: entry};
    final upserts =
        pending.upserted.map((id) => byId[id]).whereType<MealEntry>().toList();
    if (upserts.isNotEmpty) await _upsertRemote(userId, upserts);
    if (pending.deleted.isNotEmpty) {
      await Supabase.instance.client
          .from('meal_entries')
          .delete()
          .eq('user_id', userId)
          .inFilter('id', pending.deleted.toList());
    }
    await _preferences.remove('$_pendingPrefix$userId');
    await _preferences.setBool('$_migratedPrefix$userId', true);
  }

  Future<_PendingChanges> _loadPending(String userId) async {
    final source = await _preferences.getString('$_pendingPrefix$userId');
    if (source == null || source.isEmpty) return _PendingChanges();
    try {
      final json = Map<String, dynamic>.from(jsonDecode(source) as Map);
      return _PendingChanges(
        upserted: {...(json['upserted'] as List? ?? const []).cast<String>()},
        deleted: {...(json['deleted'] as List? ?? const []).cast<String>()},
      );
    } catch (_) {
      return _PendingChanges();
    }
  }

  Future<void> _queuePending(
    String userId, {
    required Iterable<String> upserted,
    required Iterable<String> deleted,
  }) async {
    final pending = await _loadPending(userId);
    for (final id in upserted) {
      pending.deleted.remove(id);
      pending.upserted.add(id);
    }
    for (final id in deleted) {
      pending.upserted.remove(id);
      pending.deleted.add(id);
    }
    await _preferences.setString(
      '$_pendingPrefix$userId',
      jsonEncode({
        'upserted': pending.upserted.toList(),
        'deleted': pending.deleted.toList(),
      }),
    );
  }

  /// Rows per request. PostgREST returns at most 1,000 rows per request
  /// by default, so the history is read in pages until a page comes back
  /// short; otherwise the newest meals were cut off after 1,000 entries.
  static const _pageSize = 1000;

  Future<List<MealEntry>> _loadRemote(String userId) async {
    final entries = <MealEntry>[];
    for (var from = 0;; from += _pageSize) {
      final rows = await Supabase.instance.client
          .from('meal_entries')
          .select()
          .eq('user_id', userId)
          .order('meal_date', ascending: true)
          .order('created_at', ascending: true)
          .order('id', ascending: true)
          .range(from, from + _pageSize - 1);
      entries.addAll((rows as List)
          .map((row) => _fromRemote(Map<String, dynamic>.from(row as Map))));
      if (rows.length < _pageSize) break;
    }
    _sort(entries);
    return entries;
  }

  Future<void> _upsertRemote(String userId, List<MealEntry> entries) =>
      Supabase.instance.client
          .from('meal_entries')
          .upsert(entries.map((entry) => _toRemote(userId, entry)).toList());

  /// Makes the cloud match [entries] exactly. Only used to finish a snapshot
  /// left by the previous sync strategy.
  Future<void> _replaceRemote(
    String userId,
    List<MealEntry> entries,
  ) async {
    final table = Supabase.instance.client.from('meal_entries');
    if (entries.isEmpty) {
      await table.delete().eq('user_id', userId);
      return;
    }

    // Upsert first. If this fails, existing cloud history remains intact.
    await _upsertRemote(userId, entries);

    // Remove stale rows only after every desired row is safely in the cloud.
    final desiredIds = entries.map((entry) => entry.id).toSet();
    final remoteRows = await table.select('id').eq('user_id', userId);
    final staleIds = [
      for (final row in remoteRows as List)
        if ((row as Map)['id']?.toString() case final id?
            when !desiredIds.contains(id))
          id,
    ];
    if (staleIds.isNotEmpty) {
      await table.delete().eq('user_id', userId).inFilter('id', staleIds);
    }
  }

  Map<String, dynamic> _toRemote(String userId, MealEntry entry) => {
        'id': entry.id,
        'user_id': userId,
        'meal_date': entry.dateKey,
        'meal_type': entry.mealType.key,
        'food_id': entry.foodId,
        'food_code': entry.foodCode,
        'food_name': entry.foodName,
        'grams': entry.grams,
        'calories': entry.calories,
        'protein_g': entry.protein,
        'carbs_g': entry.carbs,
        'fat_g': entry.fat,
        'sugar_g': entry.sugar,
        'sodium_mg': entry.sodium,
        'has_sugar_data': entry.hasSugarData,
        'has_sodium_data': entry.hasSodiumData,
        'created_at': entry.createdAt.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'components': entry.components.map((item) => item.toJson()).toList(),
      };

  MealEntry _fromRemote(Map<String, dynamic> row) {
    double number(String key) => (row[key] as num?)?.toDouble() ?? 0;
    return MealEntry(
      id: row['id'] as String? ?? '',
      dateKey: row['meal_date'] as String? ?? '',
      mealType: MealTypeLabel.fromKey(row['meal_type'] as String? ?? ''),
      foodId: (row['food_id'] as num?)?.toInt() ?? 0,
      foodCode: row['food_code'] as String? ?? '',
      foodName: row['food_name'] as String? ?? '',
      grams: number('grams'),
      calories: number('calories'),
      protein: number('protein_g'),
      carbs: number('carbs_g'),
      fat: number('fat_g'),
      sugar: number('sugar_g'),
      sodium: number('sodium_mg'),
      hasSugarData: row['has_sugar_data'] as bool? ?? false,
      hasSodiumData: row['has_sodium_data'] as bool? ?? false,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      components: (row['components'] as List<dynamic>? ?? const [])
          .map((item) =>
              MealComponent.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }

  Future<List<MealEntry>> _claimLegacyHistory(String userId) async {
    final owner = await _preferences.getString(_legacyOwnerKey);
    if (owner != null && owner != userId) return [];
    final entries = await _loadLocal(_legacyKey);
    if (entries.isNotEmpty) {
      await _preferences.setString(_legacyOwnerKey, userId);
    }
    return entries;
  }

  Future<List<MealEntry>> _loadOwnedLegacyHistory(String userId) async {
    final owner = await _preferences.getString(_legacyOwnerKey);
    if (owner != null && owner != userId) return [];
    return _loadLocal(_legacyKey);
  }

  Future<List<MealEntry>> _loadLocal(String key) async {
    final source = await _preferences.getString(key);
    if (source == null || source.isEmpty) return [];
    try {
      final decoded = jsonDecode(source) as List<dynamic>;
      final entries = decoded
          .map((item) => MealEntry.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .where((entry) => entry.id.isNotEmpty && entry.dateKey.isNotEmpty)
          .toList();
      _sort(entries);
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeLocal(String key, List<MealEntry> entries) =>
      _preferences.setString(
        key,
        jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      );

  void _sort(List<MealEntry> entries) {
    entries.sort((a, b) {
      final byDate = a.dateKey.compareTo(b.dateKey);
      return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
    });
  }
}

class _PendingChanges {
  _PendingChanges({Set<String>? upserted, Set<String>? deleted})
      : upserted = upserted ?? {},
        deleted = deleted ?? {};

  final Set<String> upserted;
  final Set<String> deleted;

  bool get isEmpty => upserted.isEmpty && deleted.isEmpty;
}
