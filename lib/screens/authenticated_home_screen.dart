import 'package:flutter/material.dart';

import '../models/fasting_settings.dart';
import '../models/health_profile.dart';
import '../services/cloud_profile_service.dart';
import '../services/fasting_settings_service.dart';
import '../services/health_calculator.dart';
import '../services/health_profile_service.dart';
import '../services/notification_service.dart';
import '../services/weight_history_service.dart';
import 'health_onboarding_screen.dart';
import 'main_shell.dart';

class AuthenticatedHomeScreen extends StatefulWidget {
  const AuthenticatedHomeScreen({super.key});
  @override
  State<AuthenticatedHomeScreen> createState() =>
      _AuthenticatedHomeScreenState();
}

class _AuthenticatedHomeScreenState extends State<AuthenticatedHomeScreen> {
  late final Future<HealthProfile?> _profile = _prepareProfile();
  late final Future<FastingSettings?> _fasting = _prepareFasting();

  /// The latest logged weight; daily energy targets follow it.
  double? _latestWeight;

  Future<HealthProfile?> _prepareProfile() async {
    try {
      await CloudProfileService.instance.syncUsernameFromMetadata();
    } catch (_) {
      // Offline: the username is synced on a later start. Without this the
      // failure hid the saved health profile and reopened onboarding.
    }
    final profile = await HealthProfileService.instance.load();
    try {
      _latestWeight = await WeightHistoryService.instance.latestWeight();
    } catch (_) {
      // Without the history the plan's starting weight is used.
    }
    return profile;
  }

  /// Loads the fasting plan and schedules its reminders again, because they
  /// are cancelled when the previous user signs out.
  Future<FastingSettings?> _prepareFasting() async {
    final settings = await FastingSettingsService.instance.load();
    if (settings != null) {
      try {
        await NotificationService.instance.scheduleFastingReminders(settings);
      } catch (_) {
        // The app still opens if reminders cannot be scheduled.
      }
    }
    return settings;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<HealthProfile?>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final profile = snapshot.data;
          if (profile == null) return const HealthOnboardingScreen();
          return FutureBuilder(
            future: _fasting,
            builder: (context, fastingSnapshot) {
              if (fastingSnapshot.connectionState != ConnectionState.done) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              final result = HealthCalculator.calculate(
                age: profile.age,
                gender: profile.gender,
                height: profile.height,
                weight: profile.currentWeight,
                targetWeight: profile.targetWeight,
                activity: profile.activity,
                experience: 'beginner',
                pregnantOrBreastfeeding: false,
                hasDiabetesOrMedication: false,
                hasEatingDisorderHistory: false,
                weightGoal: profile.weightGoal,
                targetDate: profile.targetDate,
                // The pace counts from the day the plan started; energy
                // needs follow the latest logged weight.
                planStart: profile.planStartedAt,
                latestWeight: _latestWeight,
              );
              return MainShell(
                healthResult: result,
                age: profile.age,
                fastingSettings: fastingSnapshot.data,
                onLatestWeightChanged: (weight) {
                  if (weight == _latestWeight) return;
                  setState(() => _latestWeight = weight);
                },
              );
            },
          );
        },
      );
}
