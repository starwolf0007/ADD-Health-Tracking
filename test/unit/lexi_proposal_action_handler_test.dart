import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/data/task_repository.dart';
import 'package:neuroflow/domain/reentry_note.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/intelligence/lexi_response.dart';
import 'package:neuroflow/platform/notifications/notification_service.dart';

void main() {
  late _TaskRepository repository;
  late _NotificationService notifications;
  late ProviderContainer container;

  setUp(() {
    repository = _TaskRepository(_task());
    notifications = _NotificationService();
    container = ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWithValue(repository),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('confirmed start-task proposal uses deterministic task controller',
      () async {
    await container.read(lexiProposalActionHandlerProvider).confirm(
          const LexiProposal(
            type: LexiProposalType.startTask,
            payload: {'taskId': 'task-1'},
            confirmationPrompt: 'Start it?',
          ),
        );

    expect(repository.task.status, TaskStatus.inProgress);
  });

  test('confirmed re-entry proposal saves the note and pauses the task',
      () async {
    await container.read(lexiProposalActionHandlerProvider).confirm(
          const LexiProposal(
            type: LexiProposalType.createReentryNote,
            payload: {
              'taskId': 'task-1',
              'nextAction': 'Open the document.',
            },
            confirmationPrompt: 'Save it?',
          ),
        );

    expect(repository.task.status, TaskStatus.paused);
    expect(repository.task.reentryNote?.nextAction, 'Open the document.');
  });

  test('draft-only proposal types cannot mutate task state', () async {
    await expectLater(
      container.read(lexiProposalActionHandlerProvider).confirm(
            const LexiProposal(
              type: LexiProposalType.createTaskDraft,
              payload: {'title': 'Something new'},
              confirmationPrompt: 'Create it?',
            ),
          ),
      throwsA(isA<UnsupportedError>()),
    );

    expect(repository.task.status, TaskStatus.pending);
  });

  test('completion cancels the active task notification', () async {
    await container.read(taskActionControllerProvider).complete('task-1');
    await Future<void>.delayed(Duration.zero);

    expect(repository.task.status, TaskStatus.completed);
    expect(notifications.cancelled, isTrue);
  });

  test('save for later does not double-wrap a status update failure', () async {
    repository.updateError = StateError('database unavailable');

    TaskActionFailure? failure;
    try {
      await container.read(taskActionControllerProvider).saveForLater(
            'task-1',
            ReentryNote(
              nextAction: 'Open the document.',
              updatedAt: DateTime(2026, 7, 18),
            ),
          );
    } on TaskActionFailure catch (error) {
      failure = error;
    }

    expect(failure, isNotNull);
    expect(failure!.cause, isA<StateError>());
  });
}

Task _task() => Task(
      id: 'task-1',
      title: 'Plan',
      energy: EnergyLevel.medium,
      createdAt: DateTime(2026, 7, 12),
    );

class _TaskRepository implements TaskRepository {
  _TaskRepository(this.task);

  Task task;
  Object? updateError;

  @override
  Future<Task?> getById(String id) async => id == task.id ? task : null;

  @override
  Future<void> updateStatus(String id, TaskStatus status) async {
    if (updateError case final error?) throw error;
    task = task.copyWith(
      status: status,
      activeStartedAt: status == TaskStatus.inProgress ? DateTime.now() : null,
    );
  }

  @override
  Future<void> saveReentryNote(String id, ReentryNote note) async {
    task = task.copyWith(reentryNote: note);
  }

  @override
  Future<void> clearReentryNote(String id) async {}

  @override
  Future<ReentryNote?> getReentryNote(String id) async => task.reentryNote;

  @override
  Stream<List<Task>> watchPending() => Stream.value([task]);

  @override
  Stream<List<Task>> watchTimelineForDay(
    DateTime day, {
    required bool includeFlexibleTasks,
  }) =>
      Stream.value([task]);

  @override
  Stream<int> watchCompletedTodayCount() => Stream.value(0);

  @override
  Future<void> save(Task task) async => this.task = task;

  @override
  Future<void> markComplete(String id) async {
    task = task.copyWith(status: TaskStatus.completed);
  }

  @override
  Future<void> delete(String id) async {}
}

class _NotificationService implements ActiveTaskNotificationService {
  bool cancelled = false;

  @override
  Future<bool?> areNotificationsEnabled() async => true;

  @override
  Future<void> cancelActiveTaskTimer() async => cancelled = true;

  @override
  Future<bool?> requestNotificationPermission() async => true;

  @override
  Future<void> showActiveTaskTimer({
    required String taskTitle,
    required DateTime startedAt,
  }) async {}
}
