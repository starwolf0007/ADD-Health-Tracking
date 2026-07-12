// lib/platform/notifications/notification_service.dart
//
// Local notifications. Uses inexact alarms only — SCHEDULE_EXACT_ALARM
// permission is skipped for Phase 1 (Pixel 10 Pro XL / Android 14+).
// Decision: WorkManager covers background triggers; inexact alarms cover
// in-app reminders. Exact alarms deferred to Phase 2 if user research
// shows demand.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  static const _channelId = 'neuroflow_reminders';
  static const _channelName = 'NeuroFlow Reminders';
  static const _activeTaskChannelId = 'neuroflow_active_task';
  static const _activeTaskChannelName = 'Active task timer';

  // Stable notification IDs — never reuse across categories.
  static const _idMorningBriefing = 1001;
  static const _idActiveTask = 1002;

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
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    _isInitialized = true;

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
    if (!_isInitialized) return;
    final tzScheduled = tz.TZDateTime.from(scheduledAt, tz.local);

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzScheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Immediate morning briefing notification — fired by WorkManager callback.
  /// Shows once per morning; no sound (ADHD: don't startle awake).
  /// Safe to call from a background isolate after init() has been called.
  Future<void> showMorningBriefing({required int pendingCount}) async {
    if (!_isInitialized) return;
    if (pendingCount <= 0) return; // nothing to brief about — stay quiet

    final body = pendingCount == 1
        ? 'You have 1 task today. Tap to see what\'s first.'
        : 'You have $pendingCount tasks today. Tap to see what\'s first.';

    await _plugin.show(
      id: _idMorningBriefing,
      title: 'Good morning',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false, // quiet notification — ADHD: no startle
        ),
        iOS: DarwinNotificationDetails(
          presentSound: false,
        ),
      ),
    );
  }

  /// Shows a quiet, ongoing notification with Android's native chronometer.
  /// Android updates the elapsed time itself; no Dart timer or foreground
  /// service is required while the app is alive.
  Future<void> showActiveTaskTimer({
    required String taskTitle,
    required DateTime startedAt,
  }) async {
    if (!_isInitialized) return;
    await _plugin.show(
      id: _idActiveTask,
      title: 'Working on $taskTitle',
      body: 'Tap to return when you are ready.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _activeTaskChannelId,
          _activeTaskChannelName,
          channelDescription: 'Shows the elapsed time for a running task.',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          silent: true,
          onlyAlertOnce: true,
          showWhen: true,
          when: startedAt.millisecondsSinceEpoch,
          usesChronometer: true,
        ),
        iOS: const DarwinNotificationDetails(
          // TODO(iOS): iOS has no notification chronometer equivalent. Add a
          // live-activity implementation before claiming timer parity.
          presentSound: false,
        ),
      ),
    );
  }

  Future<void> cancelActiveTaskTimer() async {
    if (!_isInitialized) return;
    await _plugin.cancel(id: _idActiveTask);
  }

  /// Returns false only when Android explicitly reports notifications disabled.
  /// Null means this platform cannot report the setting.
  Future<bool?> areNotificationsEnabled() async {
    if (!_isInitialized) return null;
    try {
      return await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
    } catch (error, stackTrace) {
      debugPrint('Unable to check NeuroFlow notification permission: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<bool?> requestNotificationPermission() async {
    if (!_isInitialized) return null;
    try {
      return await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (error, stackTrace) {
      debugPrint('Unable to request NeuroFlow notification permission: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> cancelReminder(int id) async {
    if (!_isInitialized) return;
    await _plugin.cancel(id: id);
  }

  Future<void> cancelAll() async {
    if (!_isInitialized) return;
    await _plugin.cancelAll();
  }
}
