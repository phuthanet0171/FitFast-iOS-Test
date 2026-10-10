import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/health_profile.dart';

class HealthProfileService {
  HealthProfileService._();

  static final instance = HealthProfileService._();
  static const _legacyStorageKey = 'fitfast_health_profile_v1';
  static const _legacyOwnerKey = 'fitfast_health_profile_v1_owner';
  static const _userStoragePrefix = 'fitfast_health_profile_v2_';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<HealthProfile?> load() async {
    final userId = _userId;
    if (userId == null) return _loadLocal(_legacyStorageKey);

    try {
      final remote = await _loadRemote(userId);
      if (remote != null) {
        await _saveLocal('$_userStoragePrefix$userId', remote);
        return remote;
      }
    } catch (_) {
      // Use the per-user offline cache when the network is unavailable.
    }

    final userCache = await _loadLocal('$_userStoragePrefix$userId');
    if (userCache != null) {
      await _saveRemoteSafely(userId, userCache);
      return userCache;
    }

    final legacyOwner = await _preferences.getString(_legacyOwnerKey);
    if (legacyOwner == null || legacyOwner == userId) {
      final legacy = await _loadLocal(_legacyStorageKey);
      if (legacy != null) {
        await _preferences.setString(_legacyOwnerKey, userId);
        await _saveLocal('$_userStoragePrefix$userId', legacy);
        await _saveRemoteSafely(userId, legacy);
        return legacy;
      }
    }
    return null;
  }

  Future<void> save(HealthProfile profile) async {
    final userId = _userId;
    if (userId == null) {
      await _saveLocal(_legacyStorageKey, profile);
      return;
    }
    await _saveLocal('$_userStoragePrefix$userId', profile);
    await _saveRemoteSafely(userId, profile);
  }

  Future<void> clear() async {
    final userId = _userId;
    if (userId != null) {
      await _preferences.remove('$_userStoragePrefix$userId');
      final legacyOwner = await _preferences.getString(_legacyOwnerKey);
      if (legacyOwner == userId) {
        await _preferences.remove(_legacyStorageKey);
        await _preferences.remove(_legacyOwnerKey);
      }
      return;
    }
    await _preferences.remove(_legacyStorageKey);
  }

  Future<HealthProfile?> _loadRemote(String userId) async {
    final row = await Supabase.instance.client
        .from('profiles')
        .select(
          'age, gender, height_cm, current_weight_kg, target_weight_kg, '
          'activity_level, weight_goal, updated_at',
        )
        .eq('id', userId)
        .maybeSingle();
    final (targetDate, planStartedAt) = await _loadRemotePlanDates(userId);
    if (row == null ||
        row['age'] == null ||
        row['gender'] == null ||
        row['height_cm'] == null ||
        row['current_weight_kg'] == null ||
        row['target_weight_kg'] == null ||
        row['activity_level'] == null ||
        row['weight_goal'] == null) {
      return null;
    }
    return HealthProfile(
      age: (row['age'] as num).toInt(),
      gender: row['gender'] as String,
      height: (row['height_cm'] as num).toDouble(),
      currentWeight: (row['current_weight_kg'] as num).toDouble(),
      targetWeight: (row['target_weight_kg'] as num).toDouble(),
      activity: row['activity_level'] as String,
      weightGoal: row['weight_goal'] as String,
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.now(),
      targetDate: targetDate,
      planStartedAt: planStartedAt,
    );
  }

  /// `target_date` and `plan_started_at` are newer columns; projects that
  /// have not added them yet still load the rest of the profile.
  Future<(DateTime?, DateTime?)> _loadRemotePlanDates(String userId) async {
    DateTime? read(Map<String, dynamic>? row, String column) =>
        DateTime.tryParse(row?[column] as String? ?? '');
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('target_date, plan_started_at')
          .eq('id', userId)
          .maybeSingle();
      return (read(row, 'target_date'), read(row, 'plan_started_at'));
    } on PostgrestException {
      try {
        final row = await Supabase.instance.client
            .from('profiles')
            .select('target_date')
            .eq('id', userId)
            .maybeSingle();
        return (read(row, 'target_date'), null);
      } on PostgrestException {
        return (null, null);
      }
    }
  }

  Future<void> _saveRemoteSafely(
    String userId,
    HealthProfile profile,
  ) async {
    final row = {
      'id': userId,
      'age': profile.age,
      'gender': profile.gender,
      'height_cm': profile.height,
      'current_weight_kg': profile.currentWeight,
      'target_weight_kg': profile.targetWeight,
      'activity_level': profile.activity,
      'weight_goal': profile.weightGoal,
      'updated_at': profile.updatedAt.toUtc().toIso8601String(),
    };
    final targetDate = profile.targetDate;
    final withTargetDate = {
      ...row,
      'target_date': targetDate == null
          ? null
          : '${targetDate.year.toString().padLeft(4, '0')}-'
              '${targetDate.month.toString().padLeft(2, '0')}-'
              '${targetDate.day.toString().padLeft(2, '0')}',
    };
    final client = Supabase.instance.client;
    try {
      try {
        await client.from('profiles').upsert({
          ...withTargetDate,
          'plan_started_at': profile.planStartedAt.toUtc().toIso8601String(),
        }, onConflict: 'id');
      } on PostgrestException {
        // Older databases without the newer columns still sync the rest.
        try {
          await client
              .from('profiles')
              .upsert(withTargetDate, onConflict: 'id');
        } on PostgrestException {
          await client.from('profiles').upsert(row, onConflict: 'id');
        }
      }
    } catch (_) {
      // Local data remains available and will be retried on the next load.
    }
  }

  Future<HealthProfile?> _loadLocal(String key) async {
    final source = await _preferences.getString(key);
    if (source == null || source.isEmpty) return null;
    try {
      return HealthProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(source) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLocal(String key, HealthProfile profile) =>
      _preferences.setString(key, jsonEncode(profile.toJson()));
}
