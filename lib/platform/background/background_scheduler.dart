// lib/platform/background/background_scheduler.dart
//
// WorkManager-based background trigger registration.
// Handles periodic jobs (morning plan refresh, sync queue flush).
//
// TODO(integration): WorkManager callback runs on a separate isolate.
// When real platform paths are wired (Android Application subclass +
// callbackDispatcher registration), replace stubs below.
// Flagged for Grok review lane before Phase 2.

import 'package:workmanager/workmanager.dart';

const _taskMorningRefresh = 'neuroflow.morning_refresh';
const _taskSyncFlush = 'neuroflow.sync_flush';

// Top-level function — required by WorkManager (separate isolate entry point).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    switch (taskName) {
      case _taskMorningRefresh:
        // TODO(integration): reinitialize Drift + refresh Executive plan
        break;
      case _taskSyncFlush:
        // TODO(integration): flush Google Tasks sync queue
        break;
    }
    return Future.value(true);
  });
}

class BackgroundScheduler {
  static final BackgroundScheduler _instance =
      BackgroundScheduler._internal();
  factory BackgroundScheduler() => _instance;
  BackgroundScheduler._internal();

  Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // flip to true for logcat output during dev
    );
  }

  Future<void> registerPeriodicJobs() async {
    // Morning plan refresh — runs ~6 AM, inexact by design.
    await Workmanager().registerPeriodicTask(
      _taskMorningRefresh,
      _taskMorningRefresh,
      frequency: const Duration(hours: 24),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );

    // Sync queue flush — runs every 4 hours when network available.
    await Workmanager().registerPeriodicTask(
      _taskSyncFlush,
      _taskSyncFlush,
      frequency: const Duration(hours: 4),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
