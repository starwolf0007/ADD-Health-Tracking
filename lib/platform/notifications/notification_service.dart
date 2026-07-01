// lib/platform/notifications/notification_service.dart
//
// PLATFORM LAYER. Owns local notifications directly — this is the entire
// reason the app went native (§3, v1.4): real local notifications instead of
// the ~33%-reliable web push workaround.
//
// PHASE 1 DECISION (post-review, locked): do NOT request
// `SCHEDULE_EXACT_ALARM`. Android 12+ gates exact alarms behind a permission
// the user can revoke, and Android 13+ adds a runtime check on top — that's
// real friction and a real failure mode for an app whose job is reliability.
// For v1 the bad-day nudge does not need to-the-second precision; it needs to
// land "around" the right moment. So: AndroidScheduleMode.inexactAllowWhileIdle
// for one-off notifications, and WorkManager for periodic background
// evaluation (sweep, inferred low-engagement signal). Exact alarms are a
// fast-follow if inexact proves too loose in practice — not required for v1.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

/// Payload shape for the bad-day nudge / resurfacing notification (§10
/// resolved: "outbound trigger contract" — now an in-app local notification,
/// not an external HA/Assistant payload).
class NudgePayload {
  final String taskId;
  final String title;
  final String body;
  final String deepLink; // e.g. "neuroflow://task/<id>"

  const NudgePayload({
    required this.taskId,
    required this.title,
    required this.body,
    required this.deepLink,
  });
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'neuroflow_nudges';
  static const _channelName = 'NeuroFlow';
  static const _channelDescription =
      'Gentle one-tap nudges — capped at one per day (§6).';

  Future<void> init() async {
    tzdata.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false, // calm-functional — no badge pressure (§13)
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.defaultImportance, // not high — no urgency framing (§13 no-shame)
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Fires the single, capped bad-day nudge. Frequency cap (one per day) is
  /// enforced by the caller (§6) — this method just delivers.
  Future<void> showNudgeNow(NudgePayload p) {
    return _plugin.show(
      p.taskId.hashCode,
      p.title,
      p.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          priority: Priority.defaultPriority,
          importance: Importance.defaultImportance,
        ),
        iOS: const DarwinNotificationDetails(presentBadge: false),
      ),
      payload: p.deepLink,
    );
  }

  /// Schedule a one-off nudge for later today/tomorrow — INEXACT (phase 1).
  /// Lands "around" [when], not at-the-second. Good enough for "here's one
  /// easy win"; not appropriate for a hard appointment alarm (out of scope
  /// for the nudge use case anyway).
  Future<void> scheduleInexact(NudgePayload p, DateTime when) {
    return _plugin.zonedSchedule(
      p.taskId.hashCode,
      p.title,
      p.body,
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          priority: Priority.defaultPriority,
          importance: Importance.defaultImportance,
        ),
        iOS: const DarwinNotificationDetails(presentBadge: false),
      ),
      // Inexact on purpose (phase 1 decision) — no SCHEDULE_EXACT_ALARM.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: p.deepLink,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancel(String taskId) => _plugin.cancel(taskId.hashCode);
}
