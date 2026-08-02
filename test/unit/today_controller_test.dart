import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/data/task_repository.dart';
import 'package:neuroflow/domain/mood.dart';
import 'package:neuroflow/domain/mood_repository.dart';
import 'package:neuroflow/domain/reentry_note.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/executive/planner.dart';
import 'package:neuroflow/platform/wear/wear_sync_service.dart';

void main() {
  test('Not now reselects for this session without mutating task status',
      () async {
    final first = Task(
      id: 'first',
      title: 'First suggestion',
      energy: EnergyLevel.low,
      createdAt: DateTime(2026, 7, 26, 8),
    );
    final second = Task(
      id: 'second',
      title: 'Second suggestion',
      energy: EnergyLevel.medium,
      createdAt: DateTime(2026, 7, 26, 9),
    );
    final repository = _SessionTaskRepository([first, second]);

    ProviderContainer createContainer() => ProviderContainer(
          overrides: [
            taskRepositoryProvider.overrideWithValue(repository),
            moodRepositoryProvider.overrideWithValue(const _MoodRepository()),
            wearSyncServiceProvider.overrideWithValue(_WearSyncService()),
          ],
        );

    final container = createContainer();
    addTearDown(container.dispose);
    expect(
      (await container.read(todayControllerProvider.future)).primaryTask?.id,
      'first',
    );

    await container.read(taskActionControllerProvider).notNow('first');

    expect(container.read(todayControllerProvider).value?.primaryTask?.id,
        'second');
    expect(repository.statusUpdates, isEmpty);
    expect(repository.tasks.every((task) => task.status == TaskStatus.pending),
        isTrue);

    final nextSession = createContainer();
    addTearDown(nextSession.dispose);
    expect(
      (await nextSession.read(todayControllerProvider.future)).primaryTask?.id,
      'first',
    );
  });

  test('Lexi refinement failure preserves the deterministic plan', () async {
    final task = Task(
      id: 'task-1',
      title: 'Keep the original plan',
      energy: EnergyLevel.medium,
      createdAt: DateTime(2026, 7, 26),
    );
    final container = ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWithValue(_TaskRepository(task)),
        moodRepositoryProvider.overrideWithValue(const _MoodRepository()),
        planAdvisorProvider.overrideWithValue(const _ThrowingPlanAdvisor()),
        wearSyncServiceProvider.overrideWithValue(_WearSyncService()),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(todayControllerProvider.future);

    await container
        .read(todayControllerProvider.notifier)
        .requestLexiRefinement();

    final result = container.read(todayControllerProvider);
    expect(result.hasError, isTrue);
    expect(
      result.error.toString(),
      "Lexi couldn't refine this plan. Your original plan is still available.",
    );
    expect(result.value?.primaryTask?.id, initial.primaryTask?.id);
    expect(result.value?.reason, initial.reason);
  });
}

class _SessionTaskRepository implements TaskRepository {
  final List<Task> tasks;
  final List<(String, TaskStatus)> statusUpdates = [];

  _SessionTaskRepository(this.tasks);

  @override
  Stream<List<Task>> watchPending() => Stream.value(tasks);

  @override
  Stream<List<Task>> watchTimelineForDay(
    DateTime day, {
    required bool includeFlexibleTasks,
  }) =>
      Stream.value(tasks);

  @override
  Stream<int> watchCompletedTodayCount() => Stream.value(0);

  @override
  Future<void> save(Task task) async {}

  @override
  Future<void> markComplete(String id) async {}

  @override
  Future<void> updateStatus(String id, TaskStatus status) async {
    statusUpdates.add((id, status));
  }

  @override
  Future<void> saveReentryNote(String id, ReentryNote note) async {}

  @override
  Future<void> clearReentryNote(String id) async {}

  @override
  Future<ReentryNote?> getReentryNote(String id) async => null;

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Task?> getById(String id) async {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }
}

class _TaskRepository implements TaskRepository {
  final Task task;

  const _TaskRepository(this.task);

  @override
  Stream<List<Task>> watchPending() => Stream.value([task]);

  @override
  Stream<List<Task>> watchTimelineForDay(
    DateTime day, {
    required bool includeFlexibleTasks,
  }) => Stream.value([task]);

  @override
  Stream<int> watchCompletedTodayCount() => Stream.value(0);

  @override
  Future<void> save(Task task) async {}

  @override
  Future<void> markComplete(String id) async {}

  @override
  Future<void> updateStatus(String id, TaskStatus status) async {}

  @override
  Future<void> saveReentryNote(String id, ReentryNote note) async {}

  @override
  Future<void> clearReentryNote(String id) async {}

  @override
  Future<ReentryNote?> getReentryNote(String id) async => null;

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Task?> getById(String id) async => id == task.id ? task : null;
}

class _MoodRepository implements MoodRepository {
  const _MoodRepository();

  @override
  Stream<MoodLog?> watchTodayLatest() => Stream.value(null);

  @override
  Stream<List<MoodLog>> watchRecent({int days = 14}) =>
      Stream.value(const <MoodLog>[]);

  @override
  Future<void> log(MoodLog entry) async {}
}

class _ThrowingPlanAdvisor implements PlanAdvisor {
  const _ThrowingPlanAdvisor();

  @override
  Future<Plan> refine(Plan plan, List<Task> allPending) async {
    throw StateError('Lexi unavailable');
  }
}

class _WearSyncService extends WearSyncService {
  @override
  Future<void> pushPrimaryTask(TodayState state) async {}
}
