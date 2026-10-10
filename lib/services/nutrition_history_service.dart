import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/daily_nutrition_record.dart';
import '../models/health_result.dart';

class NutritionHistoryService {
  NutritionHistoryService._();

  static final instance = NutritionHistoryService._();
  static const _legacyKey = 'fitfast_nutrition_history_v1';
  static const _legacyOwnerKey = 'fitfast_nutrition_history_v1_owner';
  static const _userKeyPrefix = 'fitfast_nutrition_history_v2_';
  static const _migratedPrefix = 'fitfast_nutrition_history_migrated_';
  static const _pendingPrefix = 'fitfast_nutrition_history_pending_';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;
  String _userKey(String userId) => '$_userKeyPrefix$userId';

  static String dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<DailyNutritionRecord> loadOrCreateToday(
    HealthResult? healthResult,
  ) async {
    final now = DateTime.now();
    final existing = await load(now);
    if (existing != null) {
      // Today's targets follow the latest health profile, so editing the
      // profile updates the dashboard at once. Earlier days keep the
      // targets they had, which is what the user was aiming for then.
      if (healthResult == null) return existing;
      final target = _emptyRecord(existing.dateKey, healthResult);
      if (_sameTargets(existing, target)) return existing;
      final updated = existing.copyWith(
        calorieTarget: target.calorieTarget,
        proteinTarget: target.proteinTarget,
        carbTarget: target.carbTarget,
        fatTarget: target.fatTarget,
        sugarLimit: target.sugarLimit,
        sodiumLimit: target.sodiumLimit,
      );
      await save(updated);
      return updated;
    }

    final record = _emptyRecord(dateKey(now), healthResult);
    await save(record);
    return record;
  }

  Future<DailyNutritionRecord?> load(DateTime date) async {
    final key = dateKey(date);
    final userId = _userId;
    if (userId == null) return (await _loadLocal(_legacyKey))[key];

    final localKey = _userKey(userId);
    final local = await _loadLocal(localKey);
    await _flushPending(userId);
    try {
      await _ensureLegacyMigrated(userId, local);
      final remote = await _loadRemoteDate(userId, key);
      if (remote == null) {
        local.remove(key);
      } else {
        local[key] = remote;
      }
      await _writeLocal(localKey, local);
      return remote;
    } catch (_) {
      return local[key] ?? await _loadOwnedLegacyDate(userId, key);
    }
  }

  Future<void> save(DailyNutritionRecord record) async {
    final userId = _userId;
    final key = userId == null ? _legacyKey : _userKey(userId);
    final records = await _loadLocal(key);
    records[record.dateKey] = record;
    await _writeLocal(key, records);
    if (userId == null) return;

    await _queuePending(userId, record);
    try {
      await _upsertRemote(userId, record);
      await _removePending(userId, record.dateKey);
      await _preferences.setBool('$_migratedPrefix$userId', true);
    } catch (_) {
      // Keep this date in the pending queue and retry on the next load.
    }
  }

  Future<void> replaceIntake({
    required DateTime date,
    required HealthResult? healthResult,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required double sugar,
    required double sodium,
    required bool sugarDataComplete,
    required bool sodiumDataComplete,
  }) async {
    final key = dateKey(date);
    final existing = key == dateKey(DateTime.now())
        ? await loadOrCreateToday(healthResult)
        : await load(date) ?? _emptyRecord(key, healthResult);
    await save(existing.copyWith(
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      sugar: sugar,
      sodium: sodium,
      sugarDataComplete: sugarDataComplete,
      sodiumDataComplete: sodiumDataComplete,
    ));
  }

  Future<void> clear() async {
    final userId = _userId;
    if (userId == null) {
      await _preferences.remove(_legacyKey);
      return;
    }
    await _preferences.remove(_userKey(userId));
    await _preferences.remove('$_pendingPrefix$userId');
  }

  static bool _sameTargets(DailyNutritionRecord a, DailyNutritionRecord b) {
    bool close(double x, double y) => (x - y).abs() < .05;
    return close(a.calorieTarget, b.calorieTarget) &&
        close(a.proteinTarget, b.proteinTarget) &&
        close(a.carbTarget, b.carbTarget) &&
        close(a.fatTarget, b.fatTarget) &&
        close(a.sugarLimit, b.sugarLimit) &&
        close(a.sodiumLimit, b.sodiumLimit);
  }

  DailyNutritionRecord _emptyRecord(
    String key,
    HealthResult? healthResult,
  ) =>
      DailyNutritionRecord(
        dateKey: key,
        calories: 0,
        protein: 0,
        carbs: 0,
        fat: 0,
        sugar: 0,
        sodium: 0,
        calorieTarget: healthResult?.calories ?? 2000,
        proteinTarget: healthResult?.protein ?? 120,
        carbTarget: healthResult?.carbs ?? 220,
        fatTarget: healthResult?.fat ?? 65,
        sugarLimit: (healthResult?.sugar ?? 24).clamp(0, 24).toDouble(),
        sodiumLimit: healthResult?.sodium ?? 2000,
      );

  Future<DailyNutritionRecord?> _loadRemoteDate(
    String userId,
    String key,
  ) async {
    final row = await Supabase.instance.client
        .from('daily_nutrition_records')
        .select()
        .eq('user_id', userId)
        .eq('record_date', key)
        .maybeSingle();
    return row == null ? null : _fromRemote(row);
  }

  Future<void> _upsertRemote(
    String userId,
    DailyNutritionRecord record,
  ) =>
      Supabase.instance.client.from('daily_nutrition_records').upsert(
            _toRemote(userId, record),
            onConflict: 'user_id,record_date',
          );

  Future<void> _ensureLegacyMigrated(
    String userId,
    Map<String, DailyNutritionRecord> local,
  ) async {
    final migrated =
        await _preferences.getBool('$_migratedPrefix$userId') ?? false;
    if (migrated) return;

    final remoteRows = await Supabase.instance.client
        .from('daily_nutrition_records')
        .select('record_date')
        .eq('user_id', userId)
        .limit(1);
    if (remoteRows.isNotEmpty) {
      await _preferences.setBool('$_migratedPrefix$userId', true);
      return;
    }

    final source = local.isNotEmpty ? local : await _claimLegacy(userId);
    if (source.isNotEmpty) {
      await Supabase.instance.client.from('daily_nutrition_records').upsert(
            source.values.map((record) => _toRemote(userId, record)).toList(),
            onConflict: 'user_id,record_date',
          );
      await _writeLocal(_userKey(userId), source);
    }
    await _preferences.setBool('$_migratedPrefix$userId', true);
  }

  Map<String, dynamic> _toRemote(
    String userId,
    DailyNutritionRecord record,
  ) =>
      {
        'user_id': userId,
        'record_date': record.dateKey,
        'calories': record.calories,
        'protein_g': record.protein,
        'carbs_g': record.carbs,
        'fat_g': record.fat,
        'sugar_g': record.sugar,
        'sodium_mg': record.sodium,
        'calorie_target': record.calorieTarget,
        'protein_target_g': record.proteinTarget,
        'carbs_target_g': record.carbTarget,
        'fat_target_g': record.fatTarget,
        'sugar_limit_g': record.sugarLimit.clamp(0, 24),
        'sodium_limit_mg': record.sodiumLimit,
        'sugar_data_complete': record.sugarDataComplete,
        'sodium_data_complete': record.sodiumDataComplete,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  DailyNutritionRecord _fromRemote(Map<String, dynamic> row) {
    double number(String key) => (row[key] as num?)?.toDouble() ?? 0;
    return DailyNutritionRecord(
      dateKey: row['record_date'] as String? ?? '',
      calories: number('calories'),
      protein: number('protein_g'),
      carbs: number('carbs_g'),
      fat: number('fat_g'),
      sugar: number('sugar_g'),
      sodium: number('sodium_mg'),
      calorieTarget: number('calorie_target'),
      proteinTarget: number('protein_target_g'),
      carbTarget: number('carbs_target_g'),
      fatTarget: number('fat_target_g'),
      sugarLimit: number('sugar_limit_g').clamp(0, 24).toDouble(),
      sodiumLimit: number('sodium_limit_mg'),
      sugarDataComplete: row['sugar_data_complete'] as bool? ?? true,
      sodiumDataComplete: row['sodium_data_complete'] as bool? ?? true,
    );
  }

  Future<void> _flushPending(String userId) async {
    final pending = await _loadPending(userId);
    if (pending.isEmpty) return;
    try {
      await Supabase.instance.client.from('daily_nutrition_records').upsert(
            pending.values.map((record) => _toRemote(userId, record)).toList(),
            onConflict: 'user_id,record_date',
          );
      await _preferences.remove('$_pendingPrefix$userId');
    } catch (_) {}
  }

  Future<void> _queuePending(
    String userId,
    DailyNutritionRecord record,
  ) async {
    final pending = await _loadPending(userId);
    pending[record.dateKey] = record;
    await _writeRecords('$_pendingPrefix$userId', pending);
  }

  Future<void> _removePending(String userId, String key) async {
    final pending = await _loadPending(userId)
      ..remove(key);
    if (pending.isEmpty) {
      await _preferences.remove('$_pendingPrefix$userId');
    } else {
      await _writeRecords('$_pendingPrefix$userId', pending);
    }
  }

  Future<Map<String, DailyNutritionRecord>> _loadPending(String userId) =>
      _loadLocal('$_pendingPrefix$userId');

  Future<Map<String, DailyNutritionRecord>> _claimLegacy(String userId) async {
    final owner = await _preferences.getString(_legacyOwnerKey);
    if (owner != null && owner != userId) return {};
    final records = await _loadLocal(_legacyKey);
    if (records.isNotEmpty) {
      await _preferences.setString(_legacyOwnerKey, userId);
    }
    return records;
  }

  Future<DailyNutritionRecord?> _loadOwnedLegacyDate(
    String userId,
    String key,
  ) async {
    final owner = await _preferences.getString(_legacyOwnerKey);
    if (owner != null && owner != userId) return null;
    return (await _loadLocal(_legacyKey))[key];
  }

  Future<Map<String, DailyNutritionRecord>> _loadLocal(String key) async {
    final source = await _preferences.getString(key);
    if (source == null || source.isEmpty) return {};
    try {
      final decoded = jsonDecode(source) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(
          key,
          DailyNutritionRecord.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeLocal(
    String key,
    Map<String, DailyNutritionRecord> records,
  ) =>
      _writeRecords(key, records);

  Future<void> _writeRecords(
    String key,
    Map<String, DailyNutritionRecord> records,
  ) =>
      _preferences.setString(
        key,
        jsonEncode(records.map((key, value) => MapEntry(key, value.toJson()))),
      );
}
