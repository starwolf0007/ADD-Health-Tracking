// lib/app/providers.dart
//
// PRESENTATION-adjacent wiring. This is the only file allowed to know about
// every layer at once — it's composition root, not logic. Plain Riverpod
// (no generator) to keep codegen surface limited to Drift for phase 1.
//
// Layering reminder (§3): Executive (planner) depends on the PlanAdvisor
// INTERFACE only. The concrete advisor (NoOpPlanAdvisor today, Lexi later)
// is chosen HERE, at the composition root — Executive code never imports
// lib/intelligence/.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/task.dart';
import '../domain/task_repository.dart';
import '../executive/planner.dart';
import '../platform/local/database.dart';
import '../platform/local/task_repository_impl.dart';
import '../platform/notifications/notification_service.dart';

// ---------------------------------------------------------------------------
// Platform layer
// ---------------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return DriftTaskRepository(ref.watch(databaseProvider));
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
  // .init() is called once at app startup (main.dart), not here — provider
  // construction should stay synchronous and side-effect-light.
});

/// Reactive open-task list — the single stream the UI and the controller
/// below both watch. Local DB is source of truth (§3 v1.4).
final openTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchOpenTasks();
});

/// Drives the §13 heartbeat line — completions today, real data not a stub.
final completedTodayCountProvider = StreamProvider<int>((ref) {
  return ref.watch(taskRepositoryProvider).watchCompletedTodayCount();
});

// ---------------------------------------------------------------------------
// Executive layer
// ---------------------------------------------------------------------------

final plannerProvider = Provider<Planner>((ref) => DeterministicPlanner());

/// Composition root for Intelligence. Defaults to the null-object advisor —
/// the app is fully usable with this provider never overridden. When the
/// Lexi platform-channel bridge (§14) lands, swap this single line (or
/// override it via ProviderScope for testing); nothing else changes.
final planAdvisorProvider = Provider<PlanAdvisor>((ref) {
  return const NoOpPlanAdvisor();
});

/// Inputs the planner needs that aren't yet backed by real features.
/// `todayMood` / `lastInteraction` are placeholders until the behavioral
/// layer (mood check-in) lands in phase 3 — wiring them is a one-line change
/// to these two providers, nothing downstream needs to know.
final todayMoodProvider = StateProvider<int?>((ref) => null);
final lastInteractionProvider = StateProvider<DateTime?>((ref) => null);

final contextSnapshotProvider = Provider<ContextSnapshot>((ref) {
  return ContextSnapshot(
    now: DateTime.now(),
    todayMood: ref.watch(todayMoodProvider),
    lastInteraction: ref.watch(lastInteractionProvider),
  );
});

// ---------------------------------------------------------------------------
// Today — the orchestration that actually calls PlanAdvisor.refine()
// ---------------------------------------------------------------------------

enum TodayMode { normal, quickWins }

class TodayState {
  final TodayMode mode;
  final List<Task> items; // deterministic order, possibly AI-refined
  final Task? primary;
  final String reason;
  const TodayState({
    required this.mode,
    required this.items,
    required this.primary,
    required this.reason,
  });
}

/// AsyncNotifier because PlanAdvisor.refine() is async (it may call an
/// on-device model later) — but note the DETERMINISTIC path never awaits
/// anything slow: NoOpPlanAdvisor.refine() resolves synchronously-fast, so
/// today's behavior has no perceptible AI latency anywhere in it.
class TodayController extends AsyncNotifier<TodayState> {
  @override
  Future<TodayState> build() async {
    final open = await ref.watch(openTasksProvider.future);
    final ctx = ref.watch(contextSnapshotProvider);
    final planner = ref.watch(plannerProvider);
    final advisor = ref.watch(planAdvisorProvider);

    final inQuickWins = planner.shouldEnterQuickWins(ctx);
    final deterministic = planner.orderedCandidates(open, ctx);

    // The ONLY call site for Intelligence in the whole app. Executive
    // produced a complete, correct `deterministic` list before this line —
    // refine() is asked to improve it, never to produce it from scratch.
    final refined = await advisor.refine(deterministic, ctx);

    final primary = refined.isNotEmpty ? refined.first : null;
    final reason = inQuickWins
        ? (primary == null
            ? "Nothing easy is tracked. Resting counts."
            : "A small one for a lighter day.")
        : (primary == null ? "Today's clear." : "Top of today.");

    return TodayState(
      mode: inQuickWins ? TodayMode.quickWins : TodayMode.normal,
      items: refined,
      primary: primary,
      reason: reason,
    );
  }

  Future<void> complete(String taskId) async {
    await ref.read(taskRepositoryProvider).complete(taskId);
    ref.invalidateSelf();
  }
}

final todayControllerProvider =
    AsyncNotifierProvider<TodayController, TodayState>(TodayController.new);
