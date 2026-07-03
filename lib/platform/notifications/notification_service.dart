// lib/platform/notifications/notification_service.dart
//
// Local notifications. Uses inexact alarms only — SCHEDULE_EXACT_ALARM
// permission is skipped for Phase 1 (Pixel 10 Pro XL / Android 14+).
// Decision: WorkManager covers background triggers; inexact alarms cover
// in-app reminders. Exact alarms deferred to Phase 2 if user research
// shows demand.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'neuroflow_reminders';
  static const _channelName = 'NeuroFlow Reminders';

  // Stable notification IDs — never reuse across categories.
  static const _idMorningBriefing = 1001;

  Future<void> init() async {
    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    // Android 13+ notification permission
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Schedule an inexact reminder. Safe on Android 14+ without
  /// SCHEDULE_EXACT_ALARM — uses inexactAllowWhileIdle so it fires
  /// even in Doze mode, within OS-controlled timing window.
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    final tzScheduled = tz.TZDateTime.from(scheduledAt, tz.local);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzScheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Immediate morning briefing notification — fired by WorkManager callback.
  /// Shows once per morning; no sound (ADHD: don't startle awake).
  /// Safe to call from a background isolate after init() has been called.
  Future<void> showMorningBriefing({required int pendingCount}) async {
    if (pendingCount <= 0) return; // nothing to brief about — stay quiet

    final body = pendingCount == 1
        ? 'You have 1 task today. Tap to see what\'s first.'
        : 'You have $pendingCount tasks today. Tap to see what\'s first.';

    await _plugin.show(
      _idMorningBriefing,
      'Good morning',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false, // quiet notification — ADHD: no startle
        ),
        iOS: const DarwinNotificationDetails(
          presentSound: false,
        ),
      ),
    );
  }

  Future<void> cancelReminder(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
