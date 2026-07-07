// lib/app/providers.dart
//
// THE composition root — the only file allowed to know every layer at once.
//
// Wiring (§3):
//   Platform (AppDatabase, lib/data/database.dart)
//     ↓
//   Data (Drift repositories: task, routine, habit, sync_queue)
//     ↓
//   Executive (Executive.evaluate → Plan; PlanAdvisor seam, §14)
//     ↓
//   Presentation (TodayController → AsyncValue<TodayState>)
//
// Rules preserved:
//   • TodayController is the SOLE call site for PlanAdvisor.refine().
//   • Executive.evaluate() stays pure/synchronous; the async AI seam is here.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/habit_repository.dart';
import '../data/habit_repository_impl.dart';
import '../data/routine_repository.dart';
import '../data/routine_repository_impl.dart';
import '../data/task_repository.dart';
import '../data/task_repository_impl.dart';
import '../domain/habit.dart';
import '../domain/routine.dart';
import '../domain/task.dart';
import '../executive/planner.dart';
import '../intelligence/lexi_plan_advisor.dart';
import '../platform/settings_service.dart';
import '../platform/sync/google_tasks_sync_service.dart';
import '../platform/sync/sync_queue_repository.dart';
import '../platform/sync/sync_queue_repository_impl.dart';
import '../platform/wear/wear_sync_service.dart';

// ---------------------------------------------------------------------------
// Platform layer
// ---------------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

// ---------------------------------------------------------------------------
// Sync layer
// ---------------------------------------------------------------------------

final syncQueueRepositoryProvider = Provider<SyncQueueRepository>((ref) {
  return DriftSyncQueueRepository(ref.watch(databaseProvider));
});

final googleTasksSyncServiceProvider = Provider<GoogleTasksSyncService>((ref) {
  return GoogleTasksSyncService(ref.watch(syncQueueRepositoryProvider));
});

final wearSyncServiceProvider = Provider<WearSyncService>((ref) {
  return WearSyncService();
});

final displayNameProvider = FutureProvider<String>((ref) async {
  return ref.watch(settingsServiceProvider).getDisplayName();
});

// ---------------------------------------------------------------------------
// Data layer
// ---------------------------------------------------------------------------

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return DriftTaskRepository(
    ref.watch(databaseProvider),
    syncQueue: ref.watch(syncQueueRepositoryProvider),
  );
});

final routineRepositoryProvider = Provider<RoutineRepository>((ref) {
  return DriftRoutineRepository(ref.watch(databaseProvider));
});

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return DriftHabitRepository(ref.watch(databaseProvider));
});

// ---------------------------------------------------------------------------
// Executive layer
// ---------------------------------------------------------------------------

final executiveProvider = Provider<Executive>((ref) => Executive());

// ---------------------------------------------------------------------------
// AI advisor tier (§14)
// ---------------------------------------------------------------------------

enum AdvisorTier {
  none,
  lexi,
  cloud,
}

final advisorTierProvider = StateProvider<AdvisorTier>((ref) {
  return AdvisorTier.lexi;
});

final planAdvisorProvider = Provider<PlanAdvisor>((ref) {
  switch (ref.watch(advisorTierProvider)) {
    case AdvisorTier.lexi:
      return LexiPlanAdvisor();
    case AdvisorTier.cloud:
      // TODO(phase3): read API key from FlutterSecureStorage
      return const CloudGeminiPlanAdvisor(apiKey: null);
    case AdvisorTier.none:
      return const NoOpPlanAdvisor();
  }
});

// ---------------------------------------------------------------------------
// Today controller — the Presentation ↔ Executive bridge
// ---------------------------------------------------------------------------

class TodayState {
  final DayMode mode;
  final Task? primaryTask;
  final List<Task> quickWins;
  final String reason;
  final bool isLoading;

  const TodayState({
    this.mode = DayMode.normal,
    this.primaryTask,
    this.quickWins = const [],
    this.reason = '',
    this.isLoading = true,
  });

  TodayState copyWith({
    DayMode? mode,
    Task? primaryTask,
    List<Task>? quickWins,
    String? reason,
    bool? isLoading,
  }) {
    return TodayState(
      mode: mode ?? this.mode,
      primaryTask: primaryTask ?? this.primaryTask,
      quickWins: quickWins ?? this.quickWins,
      reason: reason ?? this.reason,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class TodayController extends AsyncNotifier<TodayState> {
  final Set<String> _snoozedIds = {};

  @override
  Future<TodayState> build() async {
    final pending = await ref.watch(taskRepositoryProvider).watchPending().first;
    final state = await _computeState(pending);
    
    // Push to watch after state change
    ref.read(wearSyncServiceProvider).pushPrimaryTask(state);
    
    return state;
  }

  Future<TodayState> _computeState(List<Task> pending) async {
    final executive = ref.read(executiveProvider);
    final advisor = ref.read(planAdvisorProvider);

    final active = _snoozedIds.isEmpty
        ? pending
        : pending.where((t) => !_snoozedIds.contains(t.id)).toList();

    final raw = executive.evaluate(active);
    final refined = await advisor.refine(raw, active);

    return TodayState(
      mode: refined.mode,
      primaryTask: refined.primaryTask,
      quickWins: refined.quickWins,
      reason: refined.reason,
      isLoading: false,
    );
  }

  Future<void> complete(String taskId) async {
    await ref.read(taskRepositoryProvider).markComplete(taskId);
    ref.invalidateSelf();
  }

  void snoozeForSession(String taskId) {
    _snoozedIds.add(taskId);
    ref.invalidateSelf();
  }
}

final todayControllerProvider =
    AsyncNotifierProvider<TodayController, TodayState>(TodayController.new);

final completedTodayCountProvider = StreamProvider<int>((ref) {
  return ref.watch(taskRepositoryProvider).watchCompletedTodayCount();
});

final activeRoutinesProvider = StreamProvider<List<Routine>>((ref) {
  return ref.watch(routineRepositoryProvider).watchActive();
});

final dueRoutinesProvider = FutureProvider<List<Routine>>((ref) {
  return ref.watch(routineRepositoryProvider).fetchDueNow();
});

final activeHabitsProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchActive();
});
