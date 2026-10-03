import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/fasting_settings.dart';
import 'app_settings_service.dart';

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    tz.initializeTimeZones();
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
    );
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return android ?? ios ?? true;
  }

  Future<void> scheduleFastingReminders(FastingSettings settings) async {
    await initialize();
    await cancelFastingReminders();
    final appNotificationsEnabled =
        await AppSettingsService.instance.notificationsEnabled();
    if (!settings.notificationsEnabled || !appNotificationsEnabled) return;
    // A plan made on another phone turns reminders on without this device
    // ever asking. iOS then drops them silently, so ask here; the system
    // only shows its prompt once and answers at once afterwards.
    if (!await requestPermission()) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'fitfast_fasting_reminders',
        'การแจ้งเตือน IF',
        channelDescription: 'แจ้งเตือนเวลาเริ่มกินและเวลาเริ่มอดอาหาร',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      id: 1001,
      title: 'เริ่มช่วงอดอาหาร',
      body:
          'ถึงเวลาเริ่มแผน ${settings.plan} แล้ว ดูแลตัวเองและดื่มน้ำให้เพียงพอ',
      scheduledDate: _nextTime(
        settings.fastingStartHour,
        settings.fastingStartMinute,
      ),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    await _plugin.zonedSchedule(
      id: 1002,
      title: 'เริ่มรับประทานอาหารได้แล้ว',
      body: 'สิ้นสุดช่วงอดอาหาร เลือกมื้อที่มีสารอาหารครบถ้วนกัน',
      scheduledDate: _nextTime(
        settings.eatingStart.hour,
        settings.eatingStart.minute,
      ),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelFastingReminders() async {
    await initialize();
    await _plugin.cancel(id: 1001);
    await _plugin.cancel(id: 1002);
  }

  tz.TZDateTime _nextTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
