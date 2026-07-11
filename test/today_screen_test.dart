import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/data/task_repository.dart';
import 'package:neuroflow/domain/reentry_note.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/executive/today_timeline.dart';
import 'package:neuroflow/presentation/today_screen.dart';

void main() {
  final now = DateTime(2026, 7, 10, 12);

  testWidgets('renders mixed timeline and remains functional without Lexi',
      (tester) async {
    await tester.pumpWidget(_app(_mixedData(lexiAvailable: false), now));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Your plan, on device'), findsOneWidget);
    expect(find.textContaining('Lexi is offline'), findsOneWidget);
    expect(find.text('Calendar sync'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Morning anchor'), 180);
    expect(find.text('Morning anchor'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Flexible writing block').last, 180);
    expect(find.text('Flexible writing block'), findsWidgets);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('shows an empty day state', (tester) async {
    await tester.pumpWidget(_app(
        const TodayTimelineData(
          items: [],
          recommendedTask: null,
          hasCalendarPermission: false,
          lexiAvailable: false,
        ),
        now));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Your day has room'), findsOneWidget);
  });

  testWidgets('Pixel-sized screenshot layout supports large text',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_app(_mixedData(lexiAvailable: true), now));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Hey, Bryan'), findsOneWidget);
  });

  testWidgets('save for later persists full note and pauses task',
      (tester) async {
    final repository = _FakeTaskRepository(_task());
    await tester.pumpWidget(_interactiveApp(repository, now));
    await tester.pump(const Duration(milliseconds: 300));

    await _openSaveDialog(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Last completed step (Optional)'),
        'Outlined the section');
    await tester.enterText(
        find.widgetWithText(TextField, 'Exact next action (Optional)'),
        'Write the first paragraph');
    await tester.tap(find.text('Save and pause'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.task.status, TaskStatus.paused);
    expect(
        repository.task.reentryNote?.lastCompletedStep, 'Outlined the section');
    expect(
        repository.task.reentryNote?.nextAction, 'Write the first paragraph');
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('save for later accepts only next action', (tester) async {
    final repository = _FakeTaskRepository(_task());
    await tester.pumpWidget(_interactiveApp(repository, now));
    await tester.pump(const Duration(milliseconds: 300));

    await _openSaveDialog(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Exact next action (Optional)'),
        'Open the document');
    await tester.tap(find.text('Save and pause'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.task.status, TaskStatus.paused);
    expect(repository.task.reentryNote?.lastCompletedStep, isNull);
    expect(repository.task.reentryNote?.nextAction, 'Open the document');
  });

  testWidgets('save for later with no note still pauses', (tester) async {
    final repository = _FakeTaskRepository(_task());
    await tester.pumpWidget(_interactiveApp(repository, now));
    await tester.pump(const Duration(milliseconds: 300));

    await _openSaveDialog(tester);
    await tester.tap(find.text('Save and pause'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.task.status, TaskStatus.paused);
    expect(repository.task.reentryNote, isNull);
  });

  testWidgets('cancel save for later leaves task unchanged', (tester) async {
    final repository = _FakeTaskRepository(_task());
    await tester.pumpWidget(_interactiveApp(repository, now));
    await tester.pump(const Duration(milliseconds: 300));

    await _openSaveDialog(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(repository.task.status, TaskStatus.pending);
    expect(repository.task.reentryNote, isNull);
  });

  testWidgets('starting a task shows a visible running timer', (tester) async {
    final repository = _FakeTaskRepository(_task());
    await tester.pumpWidget(_interactiveApp(repository, DateTime.now()));
    await tester.pump(const Duration(milliseconds: 300));

    final startButton = find.widgetWithText(FilledButton, 'Start');
    await tester.ensureVisible(startButton);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(startButton);
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.task.status, TaskStatus.inProgress);
    expect(find.byKey(const ValueKey('active-task-timer')), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets('timeline item semantics announce type and phase',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_semanticData(), now));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.bySemanticsLabel(RegExp('Calendar event, Calendar event, current')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Fixed anchor, Anchor, upcoming')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Flexible block, Flex, upcoming')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Task, Task item, upcoming')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Open time, Open time, upcoming')),
      findsOneWidget,
    );
  });
}

Future<void> _openSaveDialog(WidgetTester tester) async {
  final list = find.byType(ListView);
  await tester.drag(list, const Offset(0, 450));
  await tester.pump(const Duration(milliseconds: 200));
  final button = find.widgetWithText(OutlinedButton, 'Save for later');
  await tester.ensureVisible(button);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(button);
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Save and pause'), findsOneWidget);
}

Widget _app(TodayTimelineData data, DateTime now) {
  return ProviderScope(
    overrides: [
      todayTimelineProvider.overrideWith((ref) async => data),
      displayNameProvider.overrideWith((ref) async => 'Bryan'),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: TodayScreen(now: now),
    ),
  );
}

Widget _interactiveApp(_FakeTaskRepository repository, DateTime now) {
  return ProviderScope(
    overrides: [
      taskRepositoryProvider.overrideWithValue(repository),
      advisorTierProvider.overrideWith(() => AdvisorTierNotifier()),
      displayNameProvider.overrideWith((ref) async => 'Bryan'),
      todayTimelineProvider.overrideWith((ref) async {
        final task = await repository.getById('task');
        return TodayTimelineData(
          items: [
            TimelineItem(
              id: 'task',
              type: TimelineItemType.flexibleBlock,
              title: task!.title,
              start: DateTime(2026, 7, 10, 13),
              task: task,
              isPaused: task.status == TaskStatus.paused,
            ),
          ],
          recommendedTask: task,
          hasCalendarPermission: true,
          lexiAvailable: false,
        );
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: TodayScreen(now: now),
    ),
  );
}

Task _task() => Task(
      id: 'task',
      title: 'Flexible writing block',
      energy: EnergyLevel.medium,
      createdAt: DateTime(2026, 7, 10, 8),
    );

TodayTimelineData _semanticData() => TodayTimelineData(
      items: [
        TimelineItem(
          id: 'calendar',
          type: TimelineItemType.calendarEvent,
          title: 'Calendar event',
          start: DateTime(2026, 7, 10, 11, 30),
          end: DateTime(2026, 7, 10, 12, 30),
        ),
        TimelineItem(
          id: 'anchor',
          type: TimelineItemType.fixedAnchor,
          title: 'Anchor',
          start: DateTime(2026, 7, 10, 13),
        ),
        TimelineItem(
          id: 'flex',
          type: TimelineItemType.flexibleBlock,
          title: 'Flex',
          start: DateTime(2026, 7, 10, 14),
        ),
        TimelineItem(
          id: 'task',
          type: TimelineItemType.task,
          title: 'Task item',
          start: DateTime(2026, 7, 10, 15),
        ),
        TimelineItem(
          id: 'open',
          type: TimelineItemType.openSpace,
          title: 'Open time',
          start: DateTime(2026, 7, 10, 16),
        ),
      ],
      recommendedTask: null,
      hasCalendarPermission: true,
      lexiAvailable: false,
    );

TodayTimelineData _mixedData({required bool lexiAvailable}) {
  final task = Task(
    id: 'task',
    title: 'Flexible writing block',
    notes: 'Draft the opening paragraph',
    energy: EnergyLevel.medium,
    createdAt: DateTime(2026, 7, 10, 8),
  );
  return TodayTimelineData(
    items: [
      TimelineItem(
        id: 'done',
        type: TimelineItemType.task,
        title: 'Breakfast',
        start: DateTime(2026, 7, 10, 8),
        isCompleted: true,
      ),
      TimelineItem(
        id: 'calendar',
        type: TimelineItemType.calendarEvent,
        title: 'Calendar sync',
        start: DateTime(2026, 7, 10, 11, 30),
        end: DateTime(2026, 7, 10, 12, 30),
      ),
      TimelineItem(
        id: 'anchor',
        type: TimelineItemType.fixedAnchor,
        title: 'Morning anchor',
        start: DateTime(2026, 7, 10, 13),
      ),
      TimelineItem(
        id: 'flex',
        type: TimelineItemType.flexibleBlock,
        title: task.title,
        start: DateTime(2026, 7, 10, 14),
        task: task,
      ),
    ],
    recommendedTask: task,
    hasCalendarPermission: true,
    lexiAvailable: lexiAvailable,
  );
}

class _FakeTaskRepository implements TaskRepository {
  Task task;
  _FakeTaskRepository(this.task);

  @override
  Stream<List<Task>> watchPending() => Stream.value([task]);

  @override
  Stream<List<Task>> watchTodayTimeline() => Stream.value([task]);

  @override
  Stream<int> watchCompletedTodayCount() => Stream.value(0);

  @override
  Future<void> save(Task value) async => task = value;

  @override
  Future<void> markComplete(String id) async =>
      task = task.copyWith(status: TaskStatus.completed);

  @override
  Future<void> updateStatus(String id, TaskStatus status) async => task = Task(
        id: task.id,
        title: task.title,
        notes: task.notes,
        energy: task.energy,
        status: status,
        createdAt: task.createdAt,
        dueDate: task.dueDate,
        completedAt: task.completedAt,
        activeStartedAt:
            status == TaskStatus.inProgress ? DateTime.now() : null,
        estimatedMinutes: task.estimatedMinutes,
        reentryNote: task.reentryNote,
        isQuickWin: task.isQuickWin,
      );

  @override
  Future<void> saveReentryNote(String id, ReentryNote note) async {
    task = task.copyWith(reentryNote: note);
  }

  @override
  Future<void> clearReentryNote(String id) async {
    task = Task(
      id: task.id,
      title: task.title,
      notes: task.notes,
      energy: task.energy,
      status: task.status,
      createdAt: task.createdAt,
      dueDate: task.dueDate,
      completedAt: task.completedAt,
      estimatedMinutes: task.estimatedMinutes,
      isQuickWin: task.isQuickWin,
    );
  }

  @override
  Future<ReentryNote?> getReentryNote(String id) async => task.reentryNote;

  @override
  Future<Task?> getById(String id) async => id == task.id ? task : null;

  @override
  Future<void> delete(String id) async {}
}
