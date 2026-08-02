import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/data/task_repository.dart';
import 'package:neuroflow/domain/mood.dart';
import 'package:neuroflow/domain/mood_repository.dart';
import 'package:neuroflow/domain/reentry_note.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/executive/planner.dart';
import 'package:neuroflow/executive/timeline_logic.dart';
import 'package:neuroflow/platform/wear/wear_sync_service.dart';
import 'package:neuroflow/presentation/today_screen.dart';

void main() {
  final now = DateTime(2026, 7, 10, 12);

  testWidgets('renders mixed timeline and remains functional without Lexi',
      (tester) async {
    await tester.pumpWidget(_app(_mixedData(lexiAvailable: false), now));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Your plan, on device'), findsOneWidget);
    expect(find.textContaining('Lexi is offline'), findsOneWidget);
    // Recommended-task card renders at the top, visible without scrolling —
    // check it here before scrolling down scrolls it out of the ListView's
    // built range.
    expect(find.text('Not now'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Calendar sync'), 150);
    expect(find.text('Calendar sync'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Morning anchor'), 180);
    expect(find.text('Morning anchor'), findsOneWidget);
    // Scroll on the section heading, not the task title: "Flexible writing
    // block" also appears in the recommended-task card near the top (same
    // fixture task is both the day's recommendation and the lone flexible
    // block), so scrolling to `.last` of that text can be satisfied by the
    // already-visible card without ever scrolling the flexible-items
    // section into the ListView's built range.
    await tester.scrollUntilVisible(find.text('Flexible tasks'), 180);
    expect(find.text('Flexible writing block'), findsWidgets);
    expect(find.text('Flexible tasks'), findsOneWidget);
  });

  testWidgets(
      'tapping the day summary card triggers Lexi refinement and shows the refined reason',
      (tester) async {
    final repository = _FakeTaskRepository(_task());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWithValue(repository),
          moodRepositoryProvider.overrideWithValue(const _FakeMoodRepository()),
          planAdvisorProvider.overrideWithValue(const _FixedReasonAdvisor()),
          wearSyncServiceProvider.overrideWithValue(_FakeWearSyncService()),
          todayTimelineProvider
              .overrideWith((ref) async => _mixedData(lexiAvailable: true)),
          displayNameProvider.overrideWith((ref) async => 'Bryan'),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: TodayScreen(now: now),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Deterministic-only on load (PR #39 intent) — the Lexi-refined reason
    // must not appear yet.
    expect(find.text('LEXI REFINED REASON MARKER'), findsNothing);

    final card = find.text('Tap to talk with Lexi');
    await tester.ensureVisible(card);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 500));

    // Tapping the day summary card is the explicit user action that opts
    // into Lexi refinement (ADR-001); it must actually reach
    // TodayController.requestLexiRefinement() and surface the result.
    expect(find.text('LEXI REFINED REASON MARKER'), findsOneWidget);
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

  testWidgets('Lexi card tap requests one opt-in refinement', (tester) async {
    final controller = _RecordingTodayController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayControllerProvider.overrideWith(() => controller),
          todayTimelineProvider.overrideWith(
            (ref) async => _mixedData(lexiAvailable: true),
          ),
          displayNameProvider.overrideWith((ref) async => 'Bryan'),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: TodayScreen(now: now),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.ensureVisible(find.text('A calm look ahead'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('A calm look ahead'));

    expect(controller.refinementRequests, 1);
  });

  testWidgets('date navigation can browse away and return to today',
      (tester) async {
    await tester.pumpWidget(_app(_mixedData(lexiAvailable: false), now));
    await tester.pump(const Duration(milliseconds: 300));

    final nextDay = find.byKey(const ValueKey('date-next-day'));
    await tester.ensureVisible(nextDay);
    await tester.tap(nextDay);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Back to Today'), findsOneWidget);
    await tester.tap(find.text('Back to Today'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Back to Today'), findsNothing);
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

  for (final context in const {
    'Missing information': 'Paused because information was missing.',
    'Energy dropped': 'Paused because energy dropped.',
    'Got interrupted': 'Paused because you got interrupted.',
    'Lost the thread': 'Paused because you lost the thread.',
  }.entries) {
    testWidgets('pause context ${context.key} maps to calm re-entry copy',
        (tester) async {
      final repository = _FakeTaskRepository(_task());
      await tester.pumpWidget(_interactiveApp(repository, now));
      await tester.pump(const Duration(milliseconds: 300));

      await _openSaveDialog(tester);
      await tester.tap(find.byKey(ValueKey('pause-context-${context.key}')));
      await tester.tap(find.text('Pause safely'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(repository.task.status, TaskStatus.paused);
      expect(repository.task.reentryNote?.lastCompletedStep, context.value);
      expect(repository.task.reentryNote?.nextAction, isNull);
    });
  }

  testWidgets('custom pause note persists and remains visible after resume',
      (tester) async {
    final repository = _FakeTaskRepository(_task());
    await tester.pumpWidget(_interactiveApp(repository, now));
    await tester.pump(const Duration(milliseconds: 300));

    await _openSaveDialog(tester);
    await tester.enterText(
        find.byKey(const ValueKey('pause-note-field')), 'Open the document');
    await tester.tap(find.text('Pause safely'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.task.status, TaskStatus.paused);
    expect(repository.task.reentryNote?.lastCompletedStep, isNull);
    expect(repository.task.reentryNote?.nextAction, 'Open the document');
    expect(find.byKey(const ValueKey('saved-return-point')), findsOneWidget);
    expect(find.text('Open the document'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.task.status, TaskStatus.inProgress);
    expect(find.byKey(const ValueKey('saved-return-point')), findsOneWidget);
    expect(find.text('Open the document'), findsOneWidget);
  });

  testWidgets('save for later with no note still pauses', (tester) async {
    final repository = _FakeTaskRepository(_task());
    await tester.pumpWidget(_interactiveApp(repository, now));
    await tester.pump(const Duration(milliseconds: 300));

    await _openSaveDialog(tester);
    await tester.tap(find.text('Pause safely'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.task.status, TaskStatus.paused);
    expect(repository.task.reentryNote, isNull);
    expect(find.text('Saved. Your return point is ready.'), findsOneWidget);
  });

  testWidgets('save for later persists an optional return time',
      (tester) async {
    final repository = _FakeTaskRepository(_task());
    await tester.pumpWidget(_interactiveApp(repository, now));
    await tester.pump(const Duration(milliseconds: 300));

    await _openSaveDialog(tester);
    await tester.tap(find.text('Return time (Optional)'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Pause safely'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.task.status, TaskStatus.paused);
    expect(repository.task.reentryNote?.returnAt, isNotNull);
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

  testWidgets('Not now selects another task and promises resurfacing',
      (tester) async {
    final repository = _TaskListRepository([
      _task().copyWith(title: 'First suggestion', energy: EnergyLevel.low),
      Task(
        id: 'second',
        title: 'Second suggestion',
        energy: EnergyLevel.medium,
        createdAt: DateTime(2026, 7, 10, 9),
      ),
    ]);
    await tester.pumpWidget(_notNowApp(repository, now));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('First suggestion'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Second suggestion'), findsOneWidget);
    expect(find.text('Okay. Iâ€™ll bring this back later.'), findsOneWidget);
    expect(repository.statusUpdates, isEmpty);
    expect(repository.tasks.every((task) => task.status == TaskStatus.pending),
        isTrue);
  });

  testWidgets('starting a task shows elapsed time and a gentle focus cue',
      (tester) async {
    final semantics = tester.ensureSemantics();
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
    expect(find.byKey(const ValueKey('gentle-focus-time-cue')), findsOneWidget);
    expect(find.bySemanticsLabel('Gentle focus-time cue'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('Running'), findsOneWidget);
    semantics.dispose();
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

  testWidgets('timeline task edit control opens the time editor',
      (tester) async {
    final repository = _FakeTaskRepository(
      _task().copyWith(dueDate: DateTime(2026, 7, 10, 14)),
    );
    await tester.pumpWidget(_interactiveApp(repository, now));
    await tester.pump(const Duration(milliseconds: 300));

    final edit = find.byKey(const ValueKey('timeline-task-edit-task'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('task-editor-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-editor-time')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('task-editor-clear-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-editor-save')), findsOneWidget);
  });

  testWidgets('capture FAB focuses task input above the keyboard inset',
      (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final repository = _FakeTaskRepository(_task());
    await tester.pumpWidget(_interactiveApp(repository, now));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Add task'));
    await tester.pump(const Duration(milliseconds: 500));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump(const Duration(milliseconds: 500));

    final captureField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == "What's on your mind?",
    );
    expect(captureField, findsOneWidget);
    final editable = find.descendant(
      of: captureField,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);

    final submit = find.widgetWithText(ElevatedButton, 'Add to today');
    expect(submit, findsOneWidget);
    final logicalHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final keyboardHeight =
        tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
    expect(tester.getRect(submit).bottom,
        lessThanOrEqualTo(logicalHeight - keyboardHeight));
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
  expect(find.text('Pause safely'), findsOneWidget);
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

Widget _notNowApp(_TaskListRepository repository, DateTime now) {
  return ProviderScope(
    overrides: [
      taskRepositoryProvider.overrideWithValue(repository),
      moodRepositoryProvider.overrideWithValue(const _FakeMoodRepository()),
      wearSyncServiceProvider.overrideWithValue(_FakeWearSyncService()),
      displayNameProvider.overrideWith((ref) async => 'Bryan'),
      todayTimelineProvider.overrideWith((ref) async {
        final recommended =
            ref.watch(todayControllerProvider).value?.primaryTask;
        return TodayTimelineData(
          items: const [],
          recommendedTask: recommended,
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
  bool deleted = false;
  _FakeTaskRepository(this.task);

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
  Future<Task?> getById(String id) async =>
      id == task.id && !deleted ? task : null;

  @override
  Future<void> delete(String id) async => deleted = true;
}

class _TaskListRepository implements TaskRepository {
  final List<Task> tasks;
  final List<(String, TaskStatus)> statusUpdates = [];

  _TaskListRepository(this.tasks);

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
  Future<Task?> getById(String id) async {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {}
}

class _RecordingTodayController extends TodayController {
  int refinementRequests = 0;

  @override
  Future<TodayState> build() async => const TodayState(isLoading: false);

  @override
  Future<void> requestLexiRefinement() async {
    refinementRequests++;
  }
}

class _FakeMoodRepository implements MoodRepository {
  const _FakeMoodRepository();

  @override
  Stream<MoodLog?> watchTodayLatest() => Stream.value(null);

  @override
  Stream<List<MoodLog>> watchRecent({int days = 14}) =>
      Stream.value(const <MoodLog>[]);

  @override
  Future<void> log(MoodLog entry) async {}
}

class _FixedReasonAdvisor implements PlanAdvisor {
  const _FixedReasonAdvisor();

  @override
  Future<Plan> refine(Plan plan, List<Task> allPending) async {
    return Plan(
      mode: plan.mode,
      primaryTask: plan.primaryTask,
      quickWins: plan.quickWins,
      reason: 'LEXI REFINED REASON MARKER',
    );
  }
}

class _FakeWearSyncService extends WearSyncService {
  @override
  Future<void> pushPrimaryTask(TodayState state) async {}
}
