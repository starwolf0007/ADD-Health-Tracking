// lib/platform/daily_reset.dart
//
// Daily reset — resets all routine step completion flags once per calendar day.
//
// Called from main() before runApp. Uses FlutterSecureStorage to persist the
// last reset date across app restarts.
//
// Why on startup rather than WorkManager?
//   WorkManager fires at OS-controlled times and may be delayed by Doze.
//   A startup check is instant and covers the case where the app is opened
//   on a new day before WorkManager has had a chance to fire.
//
// ADHD rationale: waking up to a fresh routine list every morning removes
// the friction of manually resetting yesterday's completed steps.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

const _kLastResetKey = 'neuroflow_last_routine_reset';

/// Call once during app startup (before runApp) with the shared
/// ProviderContainer. No-ops if already reset today.
Future<void> resetRoutinesIfNewDay(ProviderContainer container) async {
  try {
    const storage = FlutterSecureStorage();
    final today = _todayKey();
    final lastReset = await storage.read(key: _kLastResetKey);

    if (lastReset == today) return; // already reset today

    // New day — reset all active routine steps.
    final repo = container.read(routineRepositoryProvider);
    final routines = await repo.watchActive().first;
    for (final routine in routines) {
      await repo.resetRoutine(routine.id);
    }

    // Record today so we don't reset again until tomorrow.
    await storage.write(key: _kLastResetKey, value: today);
  } catch (_) {
    // Non-fatal — worst case the user sees yesterday's step state.
  }
}

/// ISO-8601 date string for today in local time, e.g. "2026-06-30".
String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
