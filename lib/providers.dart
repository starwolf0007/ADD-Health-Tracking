// lib/providers.dart
//
// Riverpod composition root. Wires the four-layer architecture:
//   Platform  (database)
//   ↓
//   Data      (repository)
//   ↓
//   Executive (planner + advisor seam)
//   ↓
//   Presentation (TodayController → TodayState)
//
// Rule: TodayController is the SOLE call site for PlanAdvisor.refine().
// Executive.evaluate() is pure/synchronous; the async AI seam lives here.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'data/habit_repository.dart';
import 'data/habit_repository_impl.dart';
import 'data/routine_repository.dart';
import 'data/routine_repository_impl.dart';
import 'data/task_repository.dart';
import 'data/task_repository_impl.dart';
import 'domain/habit.dart';
import 'domain/routine.dart';
import 'domain/task.dart';
import 'executive/lexi_plan_advisor.dart';
import 'executive/planner.dart';
import 'platform/settings_service.dart';
import 'platform/sync/google_tasks_sync_service.dart';
import 'platform/sync/sync_queue_repository.dart';
import 'platform/sync/sync_queue_repository_impl.dart';
import 'platform/wear/wear_sync_service.dart';

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

/// Google Tasks sync service — dormant until user connects Google Tasks.
/// Call GoogleTasksSyncService.saveToken() after OAuth to activate.
final googleTasksSyncServiceProvider = Provider<GoogleTasksSyncService>((ref) {
  return GoogleTasksSyncService(ref.watch(syncQueueRepositoryProvider));
});

/// Wear OS sync service — pushes primary task to Pixel Watch 4.
/// No-ops gracefully if watch is unpaired or running on simulator.
final wearSyncServiceProvider = Provider<WearSyncService>((ref) {
  return WearSyncService();
});

/// User's display name — drives the greeting on TodayScreen.
/// Async because it reads from FlutterSecureStorage.
final displayNameProvider = FutureProvider<String>((ref) async {
  return ref.watch(settingsServiceProvider).getDisplayName();
});

/// Global Privacy & Health Sync opt-in. Default: off (privacy-first design).
/// Gates permission to sync health data to Apple Health / Google Health.
/// TODO(phase3): Actual sync logic hooks in Phase 3 when health platform integrations
/// (HealthKit / Google Fit) are fully wired.
final globalPrivacyProvider = StateProvider<bool>((ref) {
  return false; // default off — users must explicitly opt-in
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
  /// Phase 1: fully deterministic, no AI. Default.
  none,
  /// Phase 2: on-device Gemini Nano via platform channel. Default when available.
  lexi,
  /// Phase 3: cloud Gemini — explicit user opt-in only, never default.
  cloud,
}

/// User's chosen advisor tier. Defaults to lexi (gracefully falls back to NoOp
/// if Gemini Nano is unavailable on the device).
final advisorTierProvider = StateProvider<AdvisorTier>((ref) {
  return AdvisorTier.lexi; // will silently NoOp until native bridge is wired
});

/// Active PlanAdvisor — swaps based on advisorTierProvider.
/// TodayController is the SOLE call site for refine().
final planAdvisorProvider = Provider<PlanAdvisor>((ref) {
  final tier = ref.watch(advisorTierProvider);
  switch (tier) {
    case AdvisorTier.lexi:
      return LexiPlanAdvisor();
    case AdvisorTier.cloud:
      // TODO(phase3): read API key from FlutterSecureStorage before constructing
      return const CloudGeminiPlanAdvisor(apiKey: null);
    case AdvisorTier.none:
      return const NoOpPlanAdvisor();
  }
});

// ---------------------------------------------------------------------------
// TodayState — what the Presentation layer consumes
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

// ---------------------------------------------------------------------------
// TodayController — the Presentation ↔ Executive bridge
// ---------------------------------------------------------------------------

class TodayController extends AsyncNotifier<TodayState> {
  /// Tasks snoozed for this session only (no DB write).
  /// Cleared on app restart or when the stream rebuilds from a new day reset.
  final Set<String> _snoozedIds = {};

  @override
  Future<TodayState> build() async {
    // Watch pending tasks; rebuild whenever they change.
    final pending = await ref
        .watch(taskRepositoryProvider)
        .watchPending()
        .first;

    final nextState = await _computeState(pending);

    // Push to watch after every state change — no-ops if unpaired.
    ref.read(wearSyncServiceProvider).pushPrimaryTask(nextState);

    return nextState;
  }

  Future<TodayState> _computeState(List<Task> pending) async {
    final executive = ref.read(executiveProvider);
    final advisor = ref.read(planAdvisorProvider);

    // Filter out session-snoozed tasks before planning.
    final active = _snoozedIds.isEmpty
        ? pending
        : pending.where((t) => !_snoozedIds.contains(t.id)).toList();

    // 1. Deterministic plan from Executive.
    final raw = executive.evaluate(active);

    // 2. Optional AI refinement — TodayController is the ONLY call site.
    final refined = await advisor.refine(raw, active);

    return TodayState(
      mode: refined.mode,
      primaryTask: refined.primaryTask,
      quickWins: refined.quickWins,
      reason: refined.reason,
      isLoading: false,
    );
  }

  /// Mark a task complete and recompute plan.
  Future<void> complete(String taskId) async {
    await ref.read(taskRepositoryProvider).markComplete(taskId);
  }

  /// Add a new task from the capture sheet.
  Future<void> addTask(Task task) async {
    await ref.read(taskRepositoryProvider).save(task);
  }

  /// Snooze a task for this session only (no DB write).
  /// Called by WearActionHandler when user swipes "Too hard" on watch,
  /// and available from the phone UI too.
  void snoozeForSession(String taskId) {
    _snoozedIds.add(taskId);
    // Force a recompute by invalidating self — stream will rebuild state
    // with the snoozed task excluded.
    ref.invalidateSelf();
  }
}

final todayControllerProvider =
    AsyncNotifierProvider<TodayController, TodayState>(TodayController.new);

/// Heartbeat line stream — completed-today count.
final completedTodayCountProvider = StreamProvider<int>((ref) {
  return ref.watch(taskRepositoryProvider).watchCompletedTodayCount();
});

// ---------------------------------------------------------------------------
// Routine providers
// ---------------------------------------------------------------------------

/// All active routines — drives the routine cards on Today screen.
final activeRoutinesProvider = StreamProvider<List<Routine>>((ref) {
  return ref.watch(routineRepositoryProvider).watchActive();
});

/// Routines due right now (time-of-day aware).
final dueRoutinesProvider = FutureProvider<List<Routine>>((ref) {
  return ref.watch(routineRepositoryProvider).fetchDueNow();
});

// ---------------------------------------------------------------------------
// Habit providers
// ---------------------------------------------------------------------------

/// All active habits with recent check-ins — drives HabitsWidget.
final activeHabitsProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchActive();
});
