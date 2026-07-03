// lib/app/providers.dart
//
// THE composition root — the only file allowed to know every layer at once.
// Replaces the former duplicate at lib/providers.dart (delete that file).
//
// Wiring (§3):
//   Platform (AppDatabase, lib/data/database.dart)
//     ↓
//   Data (Drift repositories: task, routine, habit, note, mood)
//     ↓
//   Executive (Executive.evaluate → Plan; PlanAdvisor seam, §14)
//     ↓
//   Presentation (TodayController → AsyncValue<Plan>)
//
// Rules preserved:
//   • TodayController is the SOLE call site for PlanAdvisor.refine().
//   • Executive.evaluate() stays pure/synchronous; the async AI seam is here.
//   • The mood signal is READ here and passed INTO evaluate() as data — the
//     Executive still performs no I/O, so determinism holds (§6 trigger).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/habit_repository.dart';
import '../data/habit_repository_impl.dart';
import '../data/mood_repository.dart';
import '../data/note_repository.dart';
import '../data/routine_repository.dart';
import '../data/routine_repository_impl.dart';
import '../data/task_repository.dart';
import '../data/task_repository_impl.dart';
import '../domain/habit.dart';
import '../domain/mood.dart';
import '../domain/note.dart';
import '../domain/routine.dart';
import '../domain/task.dart';
import '../executive/planner.dart';
import '../intelligence/lexi_plan_advisor.dart';

// ---------------------------------------------------------------------------
// Platform layer
// ---------------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ---------------------------------------------------------------------------
// Data layer
// ---------------------------------------------------------------------------

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return DriftTaskRepository(ref.watch(databaseProvider));
});

final routineRepositoryProvider = Provider<RoutineRepository>((ref) {
  return DriftRoutineRepository(ref.watch(databaseProvider));
});

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return DriftHabitRepository(ref.watch(databaseProvider));
});

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return DriftNoteRepository(ref.watch(databaseProvider));
});

final moodRepositoryProvider = Provider<MoodRepository>((ref) {
  return DriftMoodRepository(ref.watch(databaseProvider));
});

/// Reactive open-task list — the single stream the controller watches.
/// Local Drift is source of truth (§12.3); Google Tasks is a mirror.
final pendingTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchPending();
});

/// Drives the §13 heartbeat — real completions today, never a stub.
final completedTodayCountProvider = StreamProvider<int>((ref) {
  return ref.watch(taskRepositoryProvider).watchCompletedTodayCount();
});

final activeHabitsProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchActive();
});

/// Routines due right now (anchor window match). FutureProvider on purpose:
/// re-evaluated when the Today screen rebuilds, cheap DB read.
final dueRoutinesProvider = FutureProvider<List<Routine>>((ref) {
  return ref.watch(routineRepositoryProvider).fetchDueNow();
});

/// All active routines (for the Routines tab).
final activeRoutinesProvider = StreamProvider<List<Routine>>((ref) {
  return ref.watch(routineRepositoryProvider).watchActive();
});

/// Notes, pinned first then newest (for the Notes tab).
final activeNotesProvider = StreamProvider<List<Note>>((ref) {
  return ref.watch(noteRepositoryProvider).watchAll();
});

/// Today's latest mood check-in, or null. Drives the §6 Quick Wins trigger.
final todayMoodProvider = StreamProvider<MoodLog?>((ref) {
  return ref.watch(moodRepositoryProvider).watchToday();
});

/// Trailing-week mood history (for the Reflect week strip).
final recentMoodsProvider = StreamProvider<List<MoodLog>>((ref) {
  return ref.watch(moodRepositoryProvider).watchRecent(days: 7);
});

// ---------------------------------------------------------------------------
// Executive layer
// ---------------------------------------------------------------------------

final executiveProvider = Provider<Executive>((ref) => Executive());

// ---------------------------------------------------------------------------
// AI advisor tier (§14)
// ---------------------------------------------------------------------------

enum AdvisorTier {
  /// Phase 1: fully deterministic, no AI. App is complete without AI.
  none,

  /// Phase 2: on-device Gemini Nano via platform channel.
  lexi,

  /// Phase 3: cloud Gemini — explicit user opt-in only, never default.
  cloud,
}

/// Chosen tier. LexiPlanAdvisor silently NoOps until the native bridge lands.
final advisorTierProvider = StateProvider<AdvisorTier>((ref) {
  return AdvisorTier.lexi;
});

/// Active PlanAdvisor — TodayController is the SOLE call site for refine().
final planAdvisorProvider = Provider<PlanAdvisor>((ref) {
  switch (ref.watch(advisorTierProvider)) {
    case AdvisorTier.lexi:
      return LexiPlanAdvisor();
    case AdvisorTier.cloud:
      // TODO(phase3): read API key from FlutterSecureStorage first (§2.8).
      return const CloudGeminiPlanAdvisor(apiKey: null);
    case AdvisorTier.none:
      return const NoOpPlanAdvisor();
  }
});

// ---------------------------------------------------------------------------
// Today controller — the Presentation ↔ Executive bridge
// ---------------------------------------------------------------------------

/// The UI consumes the executive's [Plan] directly.
class TodayController extends AsyncNotifier<Plan> {
  @override
  Future<Plan> build() async {
    final pending = await ref.watch(pendingTasksProvider.future);
    final mood = ref.watch(todayMoodProvider).valueOrNull;
    final executive = ref.watch(executiveProvider);
    final advisor = ref.watch(planAdvisorProvider);

    // Executive produces a complete, correct plan deterministically —
    // today's mood is passed IN as data (§6 trigger). refine() may improve
    // the result, never produce it. Must never throw (§14).
    final deterministic = executive.evaluate(pending, mood: mood?.level);
    return advisor.refine(deterministic, pending);
  }

  Future<void> complete(String taskId) async {
    await ref.read(taskRepositoryProvider).markComplete(taskId);
    // pendingTasksProvider is a stream — Drift emits and build() re-runs.
  }
}

final todayControllerProvider =
    AsyncNotifierProvider<TodayController, Plan>(TodayController.new);
