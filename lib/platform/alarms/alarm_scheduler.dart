// lib/platform/alarms/alarm_scheduler.dart
//
// Flutter-side interface to the native ExactAlarmScheduler (Android).
//
// WorkManager is kept for the 4h sync flush — inexact is fine for network
// tasks. The morning briefing uses an exact AlarmManager alarm because
// timing is critical for ADHD users with time-blindness.
//
// Platform channel: 'neuroflow/alarms'
//   scheduleMorning(hour: int, minute: int) — schedule/reschedule alarm
//   cancelMorning()                         — cancel (if user disables briefing)
//
// Called from:
//   main.dart (initial schedule on launch)
//   settings_screen.dart (when user toggles morning briefing)

import 'package:flutter/services.dart';

const _kChannel = 'neuroflow/alarms';
const _kSchedule = 'scheduleMorning';
const _kCancel = 'cancelMorning';

class AlarmScheduler {
  static const _channel = MethodChannel(_kChannel);

  /// Schedule the morning briefing exact alarm.
  /// Defaults to 8:00 AM if [hour]/[minute] not provided.
  /// Safe to call every app launch — cancels any existing alarm first.
  static Future<void> scheduleMorning({int hour = 8, int minute = 0}) async {
    try {
      await _channel.invokeMethod<void>(_kSchedule, {
        'hour': hour,
        'minute': minute,
      });
    } on PlatformException catch (_) {
      // Non-fatal — WorkManager periodic task provides degraded fallback.
    } on MissingPluginException catch (_) {
      // Running on simulator or before native channel is wired.
    }
  }

  /// Cancel the morning briefing alarm.
  /// Call when user disables morning briefing in Settings.
  static Future<void> cancelMorning() async {
    try {
      await _channel.invokeMethod<void>(_kCancel);
    } on PlatformException catch (_) {
      // Non-fatal.
    } on MissingPluginException catch (_) {
      // Non-fatal.
    }
  }
}
