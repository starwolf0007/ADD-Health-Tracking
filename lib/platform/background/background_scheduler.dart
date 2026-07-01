// lib/platform/background/background_scheduler.dart
//
// PLATFORM LAYER. Periodic background evaluation via WorkManager — the
// phase-1 companion to inexact local notifications (notification_service.dart).
//
// Two periodic jobs, both tolerant of imprecise timing by design:
//   1. quickWinsEval  — re-evaluate ContextSnapshot (inferred low-engagement
//      signal, §10) and fire the capped bad-day nudge if warranted and not
//      already sent today.
//   2. sweepEval      — resurface-then-archive pass (§6): 14d untouched ->
//      resurface once, 21d -> archive.
//
// WorkManager's Android minimum periodic interval is 15 minutes; iOS
// background processing is similarly best-effort. Neither job needs
// to-the-second precision — both are "check roughly hourly" by nature, which
// is exactly why WorkManager (not an exact alarm) is the right primitive here.

import 'package:workmanager/workmanager.dart';

const String kQuickWinsEvalTask = 'neuroflow.quickWinsEval';
const String kSweepEvalTask = 'neuroflow.sweepEval';

/// Registered once at app startup. The actual work runs in
/// [callbackDispatcher] on a background isolate — it must re-open the
/// database itself (no shared state with the UI isolate).
class BackgroundScheduler {
  Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  Future<void> registerPeriodicJobs() async {
    // Hourly is plenty for an inferred-engagement check; WorkManager will
    // still only run it roughly on schedule, which is fine (no shame in a
    // nudge landing a few minutes late).
    await Workmanager().registerPeriodicTask(
      kQuickWinsEvalTask,
      kQuickWinsEvalTask,
      frequency: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.notRequired),
    );

    // Sweep doesn't need to be frequent — once a day is enough; the dates
    // it's comparing against move in whole days anyway (§6: 14d / 21d).
    await Workmanager().registerPeriodicTask(
      kSweepEvalTask,
      kSweepEvalTask,
      frequency: const Duration(hours: 24),
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
  }
}

/// Top-level, must be annotated with @pragma('vm:entry-point') in the real
/// build (Workmanager requirement) — added at integration time since it's a
/// platform-registration detail, not a logic concern.
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case kQuickWinsEvalTask:
        // TODO(integration): construct AppDatabase + DriftTaskRepository +
        // DeterministicPlanner fresh in this isolate, build a ContextSnapshot,
        // call shouldEnterQuickWins(), and if true + no nudge sent today,
        // call NotificationService().showNudgeNow(...) with the top Quick
        // Win. Wiring lives at integration time since it needs the real
        // platform DB path, not something fakeable here.
        break;
      case kSweepEvalTask:
        // TODO(integration): repository.untouchedFor(days: 14) -> resurface
        // (one local notification, "you grabbed X — still want it?"), then
        // untouchedFor(days: 21) -> repository.archive(id) for each.
        break;
    }
    return Future.value(true);
  });
}
