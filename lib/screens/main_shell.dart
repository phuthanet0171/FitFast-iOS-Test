import 'package:flutter/material.dart';

import '../models/fasting_settings.dart';
import '../models/health_result.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'fasting_timer_screen.dart';
import 'food_screen.dart';
import 'health_onboarding_screen.dart';
import 'if_interest_screen.dart';
import 'if_setup_method_screen.dart';
import 'profile_screen.dart';
import 'progress_screen.dart';
import '../widgets/app_snackbar.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.fastingSettings,
    this.healthResult,
    this.age,
  });

  final FastingSettings? fastingSettings;
  final HealthResult? healthResult;
  final int? age;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  FastingSettings? _fastingSettings;
  int _nutritionRefreshVersion = 0;

  @override
  void initState() {
    super.initState();
    _fastingSettings = widget.fastingSettings;
  }

  void _openIfSetup() {
    final healthResult = widget.healthResult;
    final age = widget.age;
    if (healthResult == null || age == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HealthOnboardingScreen()),
      );
      return;
    }
    if (age < 18) {
      _showTeenIfMessage();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IfInterestScreen(
          age: age,
          bmi: healthResult.bmi,
          healthResult: healthResult,
        ),
      ),
    );
  }

  void _openIfMethod() {
    final healthResult = widget.healthResult;
    final age = widget.age;
    if (healthResult == null || age == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HealthOnboardingScreen()),
      );
      return;
    }
    if (age < 18) {
      _showTeenIfMessage();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IfSetupMethodScreen(
          age: age,
          bmi: healthResult.bmi,
          healthResult: healthResult,
        ),
      ),
    );
  }

  void _showTeenIfMessage() {
    showAppSnackBar(
      context,
      'FitFast ไม่เปิดแผน IF อัตโนมัติสำหรับอายุ 16–17 ปี '
      'ควรปรึกษาผู้ปกครองหรือผู้เชี่ยวชาญก่อน',
      type: AppMessageType.info,
      duration: const Duration(seconds: 5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(
        healthResult: widget.healthResult,
        refreshVersion: _nutritionRefreshVersion,
      ),
      FoodScreen(
        healthResult: widget.healthResult,
        onNutritionChanged: () {
          setState(() => _nutritionRefreshVersion++);
        },
      ),
      FastingTimerScreen(
        settings: _fastingSettings,
        onSetupRequested: _openIfSetup,
        onChangePlanRequested: _openIfMethod,
        onPlanCancelled: () {
          setState(() => _fastingSettings = null);
        },
        onSettingsChanged: (settings) {
          setState(() => _fastingSettings = settings);
        },
      ),
      const ProgressScreen(),
      ProfileScreen(
        fastingSettings: _fastingSettings,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            height: 68,
            backgroundColor: Colors.white,
            elevation: 0,
            indicatorColor: AppColors.teal,
            selectedIndex: _index,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined, color: AppColors.tealDark),
                selectedIcon: Icon(Icons.home_rounded, color: Colors.white),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.ramen_dining_outlined,
                    color: AppColors.tealDark),
                selectedIcon:
                    Icon(Icons.ramen_dining_rounded, color: Colors.white),
                label: 'Food',
              ),
              NavigationDestination(
                icon: Icon(Icons.timer_outlined, color: AppColors.tealDark),
                selectedIcon: Icon(Icons.timer_rounded, color: Colors.white),
                label: 'IF',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined, color: AppColors.tealDark),
                selectedIcon:
                    Icon(Icons.bar_chart_rounded, color: Colors.white),
                label: 'Progress',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded,
                    color: AppColors.tealDark),
                selectedIcon: Icon(Icons.person_rounded, color: Colors.white),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
