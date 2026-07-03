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
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Immediate morning briefing notification. Fires now (not scheduled) —
  /// used by the background job when the day's plan is ready.
  Future<void> showMorningBriefing({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      _idMorningBriefing,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Cancel a scheduled or shown notification by ID.
  Future<void> cancel(int id) => _plugin.cancel(id);
}