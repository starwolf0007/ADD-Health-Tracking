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
import 'domain/timeline_event.dart';
import 'executive/lexi_plan_advisor.dart';
import 'executive/planner.dart';
import 'platform/settings_service.dart';
import 'platform/sync/google_tasks_sync_service.dart';
import 'platform/sync/sync_engine.dart';
import 'platform/sync/sync_engine_impl.dart';
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

// --- Generic sync engine (Google Foundation Sprint, STAGE 7) --------------
// Zero Google imports; ships with no channels registered this sprint, so it
// cannot double-process anything GoogleTasksSyncService already handles.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = DefaultSyncEngine(connectivityProbe: const SocketConnectivityProbe());
  ref.onDispose(engine.dispose);
  return engine;
});
// ---------------------------------------------------------------------------

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

  /// Resume a paused task (transitions from paused → inProgress).
  /// Phase 2 STAGE 3: Called by Re-Entry Card when user taps Resume.
  Future<void> resumePausedTask(String taskId) async {
    // Find the paused task.
    final pending = await ref
        .watch(taskRepositoryProvider)
        .watchPending()
        .first;

    final pausedTask = pending.firstWhere(
      (t) => t.id == taskId && t.status == TaskStatus.paused,
      orElse: () => throw Exception('Paused task not found: $taskId'),
    );

    // Transition to inProgress.
    final resumed = pausedTask.copyWith(status: TaskStatus.inProgress);

    // Save and recompute plan.
    await ref.read(taskRepositoryProvider).save(resumed);
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

// ---------------------------------------------------------------------------
// Paused tasks provider — Phase 2 STAGE 3: Re-Entry Card
// ---------------------------------------------------------------------------

/// All paused tasks available for re-entry (sorted by most recent first).
/// Used by Re-Entry Card to suggest task resumption.
final pausedTasksProvider = FutureProvider<List<Task>>((ref) async {
  final allPending = await ref
      .watch(taskRepositoryProvider)
      .watchPending()
      .first;

  // Filter for paused tasks only, sort by creation time (most recent first).
  final paused = allPending
      .where((t) => t.status == TaskStatus.paused)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return paused;
});

// ---------------------------------------------------------------------------
// Timeline provider (read-only projection)
// ---------------------------------------------------------------------------

/// Unified chronological timeline of all app activity.
///
/// Phase 2 STAGE 2: Merges tasks, routines, and habits into a single stream.
/// NO DATABASE TABLE — reads from existing tables and computes in memory (§4).
/// Timestamps derived from: task.createdAt (task events), routine.createdAt
/// (routine events), habit checkIn.createdAt (habit events).
///
/// Used by: Timeline view (Phase 3), re-entry card recovery logic (Phase 3 STAGE 3).
///
/// Sorted chronologically (most recent first), emitted as a read-only stream.
final timelineProvider = StreamProvider<List<TimelineEvent>>((ref) async* {
  // Watch all three sources in parallel and merge.
  final taskStream = ref.watch(taskRepositoryProvider).watchPending();
  final routineStream = ref.watch(activeRoutinesProvider);
  final habitStream = ref.watch(activeHabitsProvider);

  // Listen to all streams and emit merged timeline whenever any source changes.
  await for (final tasks in taskStream) {
    final routines = await routineStream.first;
    final habits = await habitStream.first;

    final events = <TimelineEvent>[];

    // Task events: emit task creation and state transitions.
    // For simplicity in Phase 2, emit one event per task state.
    // Phase 3: track state changes with separate timestamps per transition.
    for (final task in tasks) {
      // Create event for task creation.
      events.add(
        TaskEvent(
          taskId: task.id,
          taskTitle: task.title,
          taskNotes: task.notes,
          timestamp: task.createdAt,
          type: TimelineEventType.taskCreated,
          statusLabel: _taskStatusLabel(task.status),
          energyLabel: _energyLabel(task.energy),
        ),
      );

      // If task is complete, add completion event.
      if (task.isCompleted && task.completedAt != null) {
        events.add(
          TaskEvent(
            taskId: task.id,
            taskTitle: task.title,
            taskNotes: task.notes,
            timestamp: task.completedAt!,
            type: TimelineEventType.taskCompleted,
            statusLabel: 'Complete',
            energyLabel: _energyLabel(task.energy),
          ),
        );
      }
    }

    // Routine events: emit routine creation and completion.
    for (final routine in routines) {
      events.add(
        RoutineEvent(
          routineId: routine.id,
          routineName: routine.name,
          completedSteps: routine.completedCount,
          totalSteps: routine.steps.length,
          timestamp: routine.createdAt,
          type: TimelineEventType.routineStarted,
        ),
      );

      // If routine is complete, emit completion event.
      // Phase 2: use routine.createdAt + duration heuristic.
      // Phase 3: capture actual completedAt timestamp per routine.
      if (routine.isComplete) {
        events.add(
          RoutineEvent(
            routineId: routine.id,
            routineName: routine.name,
            completedSteps: routine.completedCount,
            totalSteps: routine.steps.length,
            timestamp: routine.createdAt.add(const Duration(hours: 1)), // heuristic
            type: TimelineEventType.routineCompleted,
          ),
        );
      }
    }

    // Habit events: emit check-in events from recent check-ins.
    for (final habit in habits) {
      for (final checkIn in habit.recentCheckIns) {
        events.add(
          HabitEvent(
            habitId: habit.id,
            habitName: habit.name,
            completed: checkIn.completed,
            currentStreak: habit.currentStreak,
            timestamp: checkIn.createdAt,
          ),
        );
      }
    }

    // Sort by timestamp (most recent first).
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    yield events;
  }
});

/// Human-readable label for task status (used in timeline).
String _taskStatusLabel(TaskStatus status) => switch (status) {
  TaskStatus.notStarted => 'Not Started',
  TaskStatus.preparing => 'Preparing',
  TaskStatus.inProgress => 'In Progress',
  TaskStatus.paused => 'Paused',
  TaskStatus.blocked => 'Blocked',
  TaskStatus.checkpoint => 'Checkpoint',
  TaskStatus.complete => 'Complete',
};

/// Human-readable label for energy level (used in timeline).
String _energyLabel(EnergyLevel energy) => switch (energy) {
  EnergyLevel.low => 'Low',
  EnergyLevel.medium => 'Medium',
  EnergyLevel.high => 'High',
};
