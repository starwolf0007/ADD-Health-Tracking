// lib/app/providers.dart
//
// THE composition root — the only file allowed to know every layer at once.

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/data/habit_repository.dart';
import 'package:neuroflow/data/habit_repository_impl.dart';
import 'package:neuroflow/data/routine_repository.dart';
import 'package:neuroflow/data/routine_repository_impl.dart';
import 'package:neuroflow/data/task_repository.dart';
import 'package:neuroflow/data/task_repository_impl.dart';
import 'package:neuroflow/domain/habit.dart';
import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/domain/reentry_note.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/executive/planner.dart';
import 'package:neuroflow/intelligence/lexi_plan_advisor.dart';
import 'package:neuroflow/intelligence/lexi_response.dart';
import 'package:neuroflow/domain/google/google_account.dart';
import 'package:neuroflow/domain/google/google_auth_repository.dart';
import 'package:neuroflow/domain/google/google_account_repository.dart';
import 'package:neuroflow/domain/google/google_permission_manager.dart';
import 'package:neuroflow/domain/google/connected_services_repository.dart';
import 'package:neuroflow/domain/google/google_connection_state.dart';
import 'package:neuroflow/domain/google/sync_engine.dart';
import 'package:neuroflow/data/google/google_auth_repository_impl.dart';
import 'package:neuroflow/data/google/google_account_repository_impl.dart';
import 'package:neuroflow/data/google/google_permission_manager_impl.dart';
import 'package:neuroflow/data/google/connected_services_repository_impl.dart';
import 'package:neuroflow/platform/google/google_service_manager.dart';
import 'package:neuroflow/platform/google/google_api_factory.dart';
import 'package:neuroflow/platform/sync/google_sync_engine_impl.dart';
import 'package:neuroflow/platform/settings_service.dart';
import 'package:neuroflow/platform/notifications/notification_service.dart';
import 'package:neuroflow/platform/sync/google_tasks_sync_service.dart';
import 'package:neuroflow/platform/sync/sync_queue_repository.dart';
import 'package:neuroflow/platform/sync/sync_queue_repository_impl.dart';
import 'package:neuroflow/platform/wear/wear_sync_service.dart';
import 'package:neuroflow/executive/today_timeline.dart';

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
// Google layer
// ---------------------------------------------------------------------------

final googleAuthRepositoryProvider = Provider<GoogleAuthRepository>((ref) {
  return GoogleAuthRepositoryImpl();
});

final googleAccountRepositoryProvider =
    Provider<GoogleAccountRepository>((ref) {
  return GoogleAccountRepositoryImpl(const FlutterSecureStorage());
});

final googlePermissionManagerProvider =
    Provider<GooglePermissionManager>((ref) {
  return GooglePermissionManagerImpl();
});

final connectedServicesRepositoryProvider =
    Provider<ConnectedServicesRepository>((ref) {
  return ConnectedServicesRepositoryImpl(const FlutterSecureStorage());
});

final googleServiceManagerProvider = Provider<GoogleServiceManager>((ref) {
  final authRepo = ref.watch(googleAuthRepositoryProvider);
  final accountRepo = ref.watch(googleAccountRepositoryProvider);
  return GoogleServiceManager(authRepo, accountRepo);
});

final googleApiFactoryProvider = Provider<GoogleApiFactory>((ref) {
  return GoogleApiFactory(ref.watch(googleServiceManagerProvider));
});

/// Stream of the currently connected Google account.
final googleAccountProvider = StreamProvider<GoogleAccount?>((ref) {
  return ref.watch(googleServiceManagerProvider).accountChanges;
});

/// Stream of the global Google connection state.
final googleConnectionStateProvider =
    StreamProvider<GoogleConnectionState>((ref) {
  return ref.watch(googleServiceManagerProvider).connectionState;
});

final googleSyncEngineProvider = Provider<SyncEngine>((ref) {
  return GoogleSyncEngineImpl(ref.watch(syncQueueRepositoryProvider));
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

class AdvisorTierNotifier extends Notifier<AdvisorTier> {
  @override
  AdvisorTier build() => AdvisorTier.lexi;

  // ignore: use_setters_to_change_properties
  void set(AdvisorTier tier) => state = tier;
}

final advisorTierProvider = NotifierProvider<AdvisorTierNotifier, AdvisorTier>(
  AdvisorTierNotifier.new,
);

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
    final pending =
        await ref.watch(taskRepositoryProvider).watchPending().first;
    final state = await _computeState(pending);

    // Push to watch after state change
    await ref.read(wearSyncServiceProvider).pushPrimaryTask(state);

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

final todayCalendarSourceProvider = Provider<TodayCalendarSource>(
  (ref) => const NoCalendarSource(),
);

final todayTimelineProvider = FutureProvider<TodayTimelineData>((ref) async {
  final tasks =
      await ref.watch(taskRepositoryProvider).watchTodayTimeline().first;
  final routines =
      await ref.watch(routineRepositoryProvider).watchActive().first;
  final calendar = ref.watch(todayCalendarSourceProvider);
  final now = DateTime.now();
  final calendarItems = await calendar.load(now);
  final recommended = ref.watch(todayControllerProvider).value?.primaryTask;
  return TodayTimelineData(
    items: const TodayTimelineBuilder().build(
      day: now,
      tasks: tasks,
      routines: routines,
      calendarItems: calendarItems,
    ),
    recommendedTask: recommended,
    hasCalendarPermission: calendar.hasPermission,
    lexiAvailable: ref.watch(advisorTierProvider) != AdvisorTier.none,
  );
});

class TaskActionFailure implements Exception {
  final String action;
  final Object cause;

  const TaskActionFailure(this.action, this.cause);
}

class TaskActionController {
  final Ref ref;
  const TaskActionController(this.ref);

  Future<void> start(String id) => _set(id, TaskStatus.inProgress);
  Future<void> resume(String id) => _set(id, TaskStatus.inProgress);
  Future<void> pause(String id) => _set(id, TaskStatus.paused);

  Future<void> saveForLater(String id, ReentryNote? note) async {
    try {
      if (note != null && !note.isEmpty) {
        await ref.read(taskRepositoryProvider).saveReentryNote(id, note);
      } else {
        await ref.read(taskRepositoryProvider).clearReentryNote(id);
      }
      await _set(id, TaskStatus.paused);
      ref.invalidate(reentryNoteProvider(id));
    } catch (error) {
      throw TaskActionFailure('save this task for later', error);
    }
  }

  Future<void> clearReentry(String id) async {
    try {
      await ref.read(taskRepositoryProvider).clearReentryNote(id);
      ref.invalidate(reentryNoteProvider(id));
      ref.invalidate(todayTimelineProvider);
    } catch (error) {
      throw TaskActionFailure('clear the saved return point', error);
    }
  }

  void notNow(String id) {
    ref.read(todayControllerProvider.notifier).snoozeForSession(id);
    ref.invalidate(todayTimelineProvider);
  }

  Future<void> _set(String id, TaskStatus status) async {
    try {
      final task = await ref.read(taskRepositoryProvider).getById(id);
      if (task == null) {
        throw StateError('Task no longer exists');
      }
      await ref.read(taskRepositoryProvider).updateStatus(id, status);
      unawaited(_updateActiveTaskNotification(task, status));
      // TodayController currently takes the first Drift stream emission instead
      // of holding a live subscription. Status affects Executive selection, so a
      // targeted rebuild is required until that controller becomes stream-based.
      ref.invalidate(todayControllerProvider);
      ref.invalidate(todayTimelineProvider);
    } catch (error) {
      throw TaskActionFailure('update this task', error);
    }
  }

  Future<void> _updateActiveTaskNotification(
      Task task, TaskStatus status) async {
    try {
      if (status == TaskStatus.inProgress) {
        await NotificationService().showActiveTaskTimer(
          taskTitle: task.title,
          startedAt: DateTime.now(),
        );
      } else {
        await NotificationService().cancelActiveTaskTimer();
      }
    } catch (error, stackTrace) {
      // Notification permission or OS notification failures must never
      // prevent the deterministic task state from updating locally.
      // Keep a dogfooding trace instead of silently discarding the failure.
      debugPrint('Could not update active task notification: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

final taskActionControllerProvider = Provider(TaskActionController.new);

abstract interface class LexiProposalActionHandler {
  Future<void> confirm(LexiProposal proposal);
}

/// The only bridge from a confirmed Lexi suggestion to deterministic app code.
/// Unsupported proposal types remain staged drafts; they cannot mutate state.
class LexiProposalController implements LexiProposalActionHandler {
  final Ref ref;

  const LexiProposalController(this.ref);

  @override
  Future<void> confirm(LexiProposal proposal) async {
    final actions = ref.read(taskActionControllerProvider);
    switch (proposal.type) {
      case LexiProposalType.startTask:
        await actions.start(_requiredPayloadString(proposal, 'taskId'));
        return;
      case LexiProposalType.pauseTask:
        await actions.pause(_requiredPayloadString(proposal, 'taskId'));
        return;
      case LexiProposalType.createReentryNote:
        final taskId = _requiredPayloadString(proposal, 'taskId');
        final returnAt = _optionalDateTime(proposal.payload['returnAt']);
        await actions.saveForLater(
          taskId,
          ReentryNote(
            lastCompletedStep:
                _optionalPayloadString(proposal.payload['lastCompletedStep']),
            nextAction: _requiredPayloadString(proposal, 'nextAction'),
            returnAt: returnAt,
            updatedAt: DateTime.now(),
          ),
        );
        return;
      case LexiProposalType.createTaskDraft:
      case LexiProposalType.createRoutineDraft:
      case LexiProposalType.setReminderDraft:
      case LexiProposalType.preparePhoneCall:
      case LexiProposalType.reduceInputMode:
        throw UnsupportedError(
          '${proposal.type.wireName} is not available in this alpha.',
        );
    }
  }

  String _requiredPayloadString(LexiProposal proposal, String key) {
    final value = proposal.payload[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    throw ArgumentError.value(value, key, 'A non-empty value is required.');
  }

  String? _optionalPayloadString(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  DateTime? _optionalDateTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }
}

final lexiProposalActionHandlerProvider = Provider<LexiProposalActionHandler>(
  LexiProposalController.new,
);

final reentryNoteProvider = FutureProvider.family<ReentryNote?, String>(
  (ref, taskId) => ref.watch(taskRepositoryProvider).getReentryNote(taskId),
);

final activeHabitsProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchActive();
});
