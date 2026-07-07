// lib/platform/background/background_scheduler.dart
//
// WorkManager-based background trigger registration.
// Handles periodic jobs (morning plan refresh, sync queue flush).
//
// Isolate safety notes (resolved):
//  • callbackDispatcher runs in a fresh Dart isolate — no shared state with main.
//  • DartPluginRegistrant.ensureInitialized() wires plugin channels in the isolate
//    before any plugin (Drift, notifications) is accessed. Required on Android 12+.
//  • AppDatabase() creates a separate SQLite connection. Safe because Drift uses
//    WAL mode by default, allowing concurrent readers/writers without corruption.
//    Always close() in finally to release the file lock.
//  • Workmanager().initialize(callbackDispatcher) from main() is sufficient.
//    No Application subclass required — the package handles registration.
//  • ExistingWorkPolicy.keep is correct for 24h periodic tasks: preserves the
//    existing schedule instead of cancelling and rescheduling on every launch.

import 'dart:ui';
import 'package:workmanager/workmanager.dart';

import '../../data/database.dart';
import '../../data/task_repository_impl.dart';
import '../notifications/notification_service.dart';
import '../sync/google_tasks_sync_service.dart';
import '../sync/sync_queue_repository_impl.dart';

const _taskMorningRefresh = 'neuroflow.morning_refresh';
const _taskSyncFlush = 'neuroflow.sync_flush';

// Top-level function — required by WorkManager (separate isolate entry point).
// Must be annotated so the Dart compiler keeps it in the release build.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // Wire Flutter plugin channels in this isolate before accessing any plugin.
    // WidgetsFlutterBinding.ensureInitialized() alone is insufficient on Android
    // 12+ in Doze; DartPluginRegistrant is the correct companion call.
    DartPluginRegistrant.ensureInitialized();

    switch (taskName) {
      case _taskMorningRefresh:
        await _runMorningRefresh();
        break;
      case _taskSyncFlush:
        await _runSyncFlush();
        break;
    }
    return Future.value(true);
  });
}

/// Counts pending tasks and shows a silent morning briefing notification.
/// Runs in the WorkManager isolate — opens its own DB connection, always closes it.
Future<void> _runMorningRefresh() async {
  final db = AppDatabase();
  try {
    final repo = DriftTaskRepository(db);
    final pending = await repo.watchPending().first;
    if (pending.isNotEmpty) {
      final svc = NotificationService();
      await svc.init();
      await svc.showMorningBriefing(pendingCount: pending.length);
    }
  } catch (_) {
    // Non-fatal — user simply doesn't get the morning nudge if something fails.
  } finally {
    await db.close();
  }
}

/// Flush pending Google Tasks sync ops from the WorkManager isolate.
/// Auth-gated: no-ops silently if user hasn't connected Google Tasks.
Future<void> _runSyncFlush() async {
  final db = AppDatabase();
  try {
    final queue = DriftSyncQueueRepository(db);
    final svc = GoogleTasksSyncService(queue);
    await svc.flush();
  } catch (_) {
    // Non-fatal — ops stay pending and will retry next flush.
  } finally {
    await db.close();
  }
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
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );

    // Sync queue flush — runs every 4 hours when network available.
    await Workmanager().registerPeriodicTask(
      _taskSyncFlush,
      _taskSyncFlush,
      frequency: const Duration(hours: 4),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
