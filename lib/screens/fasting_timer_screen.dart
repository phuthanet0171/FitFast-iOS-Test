import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/fasting_settings.dart';
import '../services/fasting_settings_service.dart';
import '../services/fasting_session_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'if_settings_screen.dart';
import '../widgets/app_snackbar.dart';
import '../services/error_messages.dart';

class FastingTimerScreen extends StatefulWidget {
  const FastingTimerScreen({
    super.key,
    required this.settings,
    required this.onSetupRequested,
    required this.onChangePlanRequested,
    required this.onSettingsChanged,
    required this.onPlanCancelled,
  });

  final FastingSettings? settings;
  final VoidCallback onSetupRequested;
  final VoidCallback onChangePlanRequested;
  final ValueChanged<FastingSettings> onSettingsChanged;
  final VoidCallback onPlanCancelled;

  @override
  State<FastingTimerScreen> createState() => _FastingTimerScreenState();
}

class _FastingTimerScreenState extends State<FastingTimerScreen>
    with WidgetsBindingObserver {
  Timer? _ticker;
  bool _updatingPreferences = false;
  bool? _lastFastingState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTicker();
    _syncSession();
  }

  @override
  void didUpdateWidget(covariant FastingTimerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _lastFastingState = null;
      _syncSession();
    }
  }

  void _syncSession() {
    final settings = widget.settings;
    if (settings == null) return;
    unawaited(
      FastingSessionService.instance
          .syncCurrentSchedule(settings)
          .catchError((_) {}),
    );
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final settings = widget.settings;
      if (!mounted || settings == null) return;
      final isFasting = _currentPhase(settings).isFasting;
      if (_lastFastingState != isFasting) {
        _lastFastingState = isFasting;
        _syncSession();
      }
      setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTicker();
      _syncSession();
      if (mounted) setState(() {});
    }
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _time(int hour, int minute) {
    return '${_twoDigits(hour)}:${_twoDigits(minute)}';
  }

  String _clock(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    return '${_twoDigits(safe.inHours)}:'
        '${_twoDigits(safe.inMinutes % 60)}:'
        '${_twoDigits(safe.inSeconds % 60)}';
  }

  _FastingPhase _currentPhase(FastingSettings settings) {
    final now = DateTime.now();
    var fastingStart = DateTime(
      now.year,
      now.month,
      now.day,
      settings.fastingStartHour,
      settings.fastingStartMinute,
    );
    if (now.isBefore(fastingStart)) {
      fastingStart = fastingStart.subtract(const Duration(days: 1));
    }

    final fastingEnd = fastingStart.add(
      Duration(hours: settings.fastingHours),
    );
    if (now.isBefore(fastingEnd)) {
      final total = Duration(hours: settings.fastingHours);
      return _FastingPhase(
        isFasting: true,
        remaining: fastingEnd.difference(now),
        progress: now.difference(fastingStart).inSeconds / total.inSeconds,
      );
    }

    final nextFastingStart = fastingStart.add(const Duration(days: 1));
    final total = Duration(hours: settings.eatingHours);
    return _FastingPhase(
      isFasting: false,
      remaining: nextFastingStart.difference(now),
      progress: now.difference(fastingEnd).inSeconds / total.inSeconds,
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IfSettingsScreen(
          onChangePlanRequested: widget.onChangePlanRequested,
          onPlanCancelled: widget.onPlanCancelled,
        ),
      ),
    );
  }

  Future<void> _applySettings(
    FastingSettings settings, {
    bool requestPermission = false,
  }) async {
    if (_updatingPreferences) return;
    setState(() => _updatingPreferences = true);
    var updated = settings;
    try {
      if (requestPermission && settings.notificationsEnabled) {
        final granted = await NotificationService.instance.requestPermission();
        if (!granted) {
          updated = settings.copyWith(notificationsEnabled: false);
          if (mounted) {
            showAppSnackBar(
              context,
              'FitFast ยังไม่ได้รับอนุญาตให้แจ้งเตือน '
              'เปิดได้ที่ ตั้งค่าเครื่อง > การแจ้งเตือน > FitFast',
              type: AppMessageType.warning,
              duration: const Duration(seconds: 5),
            );
          }
        }
      }
      await FastingSettingsService.instance.save(updated);
      await NotificationService.instance.scheduleFastingReminders(updated);
      widget.onSettingsChanged(updated);
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          friendlyError(error,
              fallback: 'บันทึกการตั้งค่า IF ไม่สำเร็จ กรุณาลองใหม่'),
          type: AppMessageType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingPreferences = false);
    }
  }

  Future<void> _pickFastingStart() async {
    final settings = widget.settings;
    if (settings == null) return;
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: settings.fastingStartHour,
        minute: settings.fastingStartMinute,
      ),
      helpText: 'เลือกเวลาเริ่มอดอาหาร',
      confirmText: 'บันทึก',
      cancelText: 'ยกเลิก',
    );
    if (value == null) return;
    await _applySettings(
      settings.copyWith(
        fastingStartHour: value.hour,
        fastingStartMinute: value.minute,
      ),
    );
  }

  Future<void> _pickEatingStart() async {
    final settings = widget.settings;
    if (settings == null) return;
    final eatingStart = settings.eatingStart;
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: eatingStart.hour,
        minute: eatingStart.minute,
      ),
      helpText: 'เลือกเวลาเริ่มรับประทาน',
      confirmText: 'บันทึก',
      cancelText: 'ยกเลิก',
    );
    if (value == null) return;
    var minutes = value.hour * 60 + value.minute - settings.fastingHours * 60;
    minutes %= 24 * 60;
    if (minutes < 0) minutes += 24 * 60;
    await _applySettings(
      settings.copyWith(
        fastingStartHour: minutes ~/ 60,
        fastingStartMinute: minutes % 60,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    if (settings == null) {
      return _NoFastingPlan(onSetupRequested: widget.onSetupRequested);
    }

    final phase = _currentPhase(settings);
    final progress = phase.progress.clamp(0.0, 1.0);
    final eatingStart = settings.eatingStart;
    final fastingStartText = _time(
      settings.fastingStartHour,
      settings.fastingStartMinute,
    );
    final eatingStartText = _time(eatingStart.hour, eatingStart.minute);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'จับเวลา IF',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton.filledTonal(
                onPressed: _openSettings,
                tooltip: 'ตั้งค่า IF',
                icon: const Icon(Icons.settings_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            phase.isFasting
                ? 'ขณะนี้อยู่ในช่วงอดอาหาร'
                : 'ขณะนี้อยู่ในช่วงรับประทานอาหาร',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: phase.isFasting
                          ? AppColors.mint
                          : AppColors.orangeSoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      phase.isFasting
                          ? 'กำลังอด • แผน ${settings.plan}'
                          : 'ช่วงกิน • แผน ${settings.plan}',
                      style: TextStyle(
                        color: phase.isFasting
                            ? AppColors.tealDark
                            : AppColors.orange,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: CustomPaint(
                      painter: _FastingRingPainter(
                        progress: progress,
                        isFasting: phase.isFasting,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              phase.isFasting
                                  ? Icons.lock_clock_rounded
                                  : Icons.restaurant_rounded,
                              color: phase.isFasting
                                  ? AppColors.teal
                                  : AppColors.orange,
                              size: 30,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              phase.isFasting
                                  ? 'เหลือเวลาก่อนเริ่มกิน'
                                  : 'เหลือเวลาก่อนเริ่มอด',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _clock(phase.remaining),
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${(progress * 100).toStringAsFixed(0)}% ของช่วงนี้',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: _TimeInfo(
                          icon: Icons.lock_outline_rounded,
                          title: 'เริ่มอด',
                          value: fastingStartText,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TimeInfo(
                          icon: Icons.restaurant_rounded,
                          title: 'เริ่มกิน',
                          value: eatingStartText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.autorenew_rounded,
                            color: AppColors.tealDark),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'ระบบจะเปลี่ยนช่วงกินและช่วงอดให้อัตโนมัติ',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ตารางประจำวัน',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Icon(
                        settings.notificationsEnabled
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_outlined,
                        color: settings.notificationsEnabled
                            ? AppColors.teal
                            : AppColors.muted,
                        size: 21,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: Row(
                      children: [
                        Expanded(
                          flex: settings.eatingHours,
                          child: const ColoredBox(
                            color: AppColors.orange,
                            child: SizedBox(height: 18),
                          ),
                        ),
                        Expanded(
                          flex: settings.fastingHours,
                          child: const ColoredBox(
                            color: AppColors.navy,
                            child: SizedBox(height: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$eatingStartText  เริ่มกิน',
                        style: const TextStyle(
                          color: AppColors.orange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$fastingStartText  เริ่มอด',
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'เวลาและการแจ้งเตือน',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (_updatingPreferences)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'แตะเวลาเพื่อปรับให้เข้ากับตารางชีวิตของคุณ',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _EditableTimeCard(
                          icon: Icons.lock_clock_outlined,
                          label: 'เริ่มอด',
                          value: fastingStartText,
                          color: AppColors.navy,
                          onTap:
                              _updatingPreferences ? null : _pickFastingStart,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _EditableTimeCard(
                          icon: Icons.restaurant_rounded,
                          label: 'เริ่มกิน',
                          value: eatingStartText,
                          color: AppColors.orange,
                          onTap: _updatingPreferences ? null : _pickEatingStart,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.notificationsEnabled,
                    onChanged: _updatingPreferences
                        ? null
                        : (value) {
                            _applySettings(
                              settings.copyWith(notificationsEnabled: value),
                              requestPermission: value,
                            );
                          },
                    secondary: Icon(
                      settings.notificationsEnabled
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      color: settings.notificationsEnabled
                          ? AppColors.teal
                          : AppColors.muted,
                    ),
                    title: const Text(
                      'แจ้งเตือนเวลาเริ่มกินและเริ่มอด',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      settings.notificationsEnabled
                          ? 'เปิดอยู่ • แจ้งเตือนทุกวัน'
                          : 'ปิดอยู่',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FastingPhase {
  const _FastingPhase({
    required this.isFasting,
    required this.remaining,
    required this.progress,
  });

  final bool isFasting;
  final Duration remaining;
  final double progress;
}

class _NoFastingPlan extends StatelessWidget {
  const _NoFastingPlan({required this.onSetupRequested});

  final VoidCallback onSetupRequested;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('จับเวลา IF',
                style: Theme.of(context).textTheme.headlineMedium),
            const Spacer(),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(
                      color: AppColors.mint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.timer_off_outlined,
                      color: AppColors.tealDark,
                      size: 45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text('ยังไม่ได้เปิดแผน IF',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 9),
                  const Text(
                    'หากเปลี่ยนใจ คุณสามารถเลือกแผน IF\nและเริ่มใช้งานได้จากที่นี่',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 250,
                    child: FilledButton.icon(
                      onPressed: onSetupRequested,
                      icon: const Icon(Icons.add_alarm_rounded),
                      label: const Text('ตั้งค่าแผน IF'),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _EditableTimeCard extends StatelessWidget {
  const _EditableTimeCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit_outlined, color: color, size: 17),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeInfo extends StatelessWidget {
  const _TimeInfo(
      {required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.tealDark, size: 22),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FastingRingPainter extends CustomPainter {
  const _FastingRingPainter({required this.progress, required this.isFasting});
  final double progress;
  final bool isFasting;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final background = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..shader = SweepGradient(
        colors: isFasting
            ? const [AppColors.teal, AppColors.blue, AppColors.orange]
            : const [AppColors.orange, Color(0xFFFFC857), AppColors.teal],
        stops: const [0, .68, 1],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, background);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * (progress == 0 ? .02 : progress),
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(covariant _FastingRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isFasting != isFasting;
  }
}
