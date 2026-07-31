// Focused coverage for issue #37 — Today must render the Quick Wins reshape
// the Executive already computes, instead of discarding it at the Presentation
// boundary.
//
// These tests drive the real seam: a low mood check-in reaches
// TodayController via DayCapacity, the real Executive selects and caps the
// list, and the screen is asserted on the resulting reshape. Nothing here
// stubs DayMode directly, because the wiring is exactly what regressed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/data/task_repository.dart';
import 'package:neuroflow/domain/mood.dart';
import 'package:neuroflow/domain/mood_repository.dart';
import 'package:neuroflow/domain/reentry_note.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/executive/timeline_logic.dart';
import 'package:neuroflow/platform/wear/wear_sync_service.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/today_screen.dart';

void main() {
  final now = DateTime(2026, 7, 10, 12);

  testWidgets('a low check-in reshapes Today into Quick Wins',
      (tester) async {
    await tester.pumpWidget(_app(mood: MoodLevel.low, now: now));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('quick-wins-card')), findsOneWidget);
    expect(find.text('Quick Wins'), findsOneWidget);
  });

  testWidgets('Quick Wins shows at most three options, lowest effort first',
      (tester) async {
    await tester.pumpWidget(_app(mood: MoodLevel.veryLow, now: now));
    await tester.pump(const Duration(milliseconds: 500));

    // Four low-energy tasks are pending; §6 caps the reshaped list at three,
    // dropping the 45-minute one.
    expect(find.byKey(const ValueKey('quick-win-t10')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-win-t15')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-win-t20')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-win-t45')), findsNothing);

    // The title says lowest effort first, so assert the rendered order rather
    // than only the membership of the set.
    double top(String id) =>
        tester.getTopLeft(find.byKey(ValueKey('quick-win-$id'))).dy;
    expect(top('t10'), lessThan(top('t15')));
    expect(top('t15'), lessThan(top('t20')));
  });

  testWidgets('the reduced view suppresses the full day but keeps commitments',
      (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app(mood: MoodLevel.low, now: now));
    await tester.pump(const Duration(milliseconds: 500));

    // Reduction is the feature: the recommended-task card, the full timeline
    // heading, and the flexible-task pile must all be absent.
    expect(find.text('Recommended now'), findsNothing);
    expect(find.text('Your day'), findsNothing);
    expect(find.text('Flexible tasks'), findsNothing);

    // Real commitments stay visible — a calm screen must not be a dishonest
    // one about a shift or an appointment.
    expect(find.text('Still fixed today'), findsOneWidget);
    expect(find.text('Morning anchor'), findsOneWidget);
    expect(find.text('Calendar sync'), findsOneWidget);
  });

  testWidgets('Quick Wins has no manual escape to the full day (§158 locked)',
      (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app(mood: MoodLevel.low, now: now));
    await tester.pump(const Duration(milliseconds: 500));

    // §158/§170: containment is the feature — no manual toggle, no user action
    // to leave or maintain the reduced state. The full day returns only when
    // the signal lifts, automatically. So there is no disclosure control and no
    // "Your day" section reachable from here.
    expect(
        find.byKey(const ValueKey('quick-wins-show-full-day')), findsNothing);
    expect(find.text('Show the full day'), findsNothing);
    expect(find.text('Back to Quick Wins'), findsNothing);
    expect(find.text('Your day'), findsNothing);

    // §163: the status label ends with the explicit permission to stop.
    expect(
      find.textContaining('Nothing else is tracked today.'),
      findsOneWidget,
    );
  });

  testWidgets('a neutral check-in leaves Today unchanged', (tester) async {
    await tester.pumpWidget(_app(mood: MoodLevel.neutral, now: now));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('quick-wins-card')), findsNothing);
    expect(find.text('Your day'), findsOneWidget);
    expect(find.text('Recommended now'), findsOneWidget);
  });

  testWidgets('no check-in at all is treated as a normal day', (tester) async {
    await tester.pumpWidget(_app(mood: null, now: now));
    await tester.pump(const Duration(milliseconds: 500));

    // Absence of evidence that the day is rough is not evidence that it is.
    expect(find.byKey(const ValueKey('quick-wins-card')), findsNothing);
    expect(find.text('Your day'), findsOneWidget);
  });

  testWidgets('the reshape is scoped to today, not to other days browsed',
      (tester) async {
    await tester.pumpWidget(_app(mood: MoodLevel.low, now: now));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('quick-wins-card')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('date-next-day')));
    await tester.pump(const Duration(milliseconds: 500));

    // Tomorrow's real schedule, not today's mood signal.
    expect(find.byKey(const ValueKey('quick-wins-card')), findsNothing);
    expect(find.text('Schedule for this day'), findsOneWidget);
  });

  testWidgets('re-deriving Today picks up a signal that arrived later',
      (tester) async {
    final moods = _FakeMoodRepository(MoodLevel.neutral);
    await tester.pumpWidget(
      _app(mood: null, now: now, moodRepository: moods),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('quick-wins-card')), findsNothing);

    // Stands in for a check-in logged on the Reflect surface, which ends with
    // ref.invalidate(todayControllerProvider).
    moods.level = MoodLevel.low;
    _container(tester).invalidate(todayControllerProvider);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('quick-wins-card')), findsOneWidget);
  });

  testWidgets('tapping a Quick Win marks it done — one-tap done (§167)',
      (tester) async {
    final tasks = _FakeTaskRepository(_pending());
    await tester.pumpWidget(
      _app(mood: MoodLevel.veryLow, now: now, taskRepository: tasks),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // The row is a done control, not a start button: one tap completes the
    // task (which drops it from the pending pool so the capped list refills),
    // rather than starting a timer that leaves it stuck as "running".
    await tester.tap(find.byKey(const ValueKey('quick-win-t10')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tasks.completed, contains('t10'));
  });

  testWidgets('Quick Wins renders no score, count, or progress figure',
      (tester) async {
    await tester.pumpWidget(_app(mood: MoodLevel.veryLow, now: now));
    await tester.pump(const Duration(milliseconds: 500));

    // §13: no visible numeric self-judgment. The short list is the message.
    expect(find.textContaining('3 of'), findsNothing);
    expect(find.textContaining('/3'), findsNothing);
    expect(find.text('3'), findsNothing);
  });
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(TodayScreen)));

/// Widget tests default to an 800x600 surface. The reduced Quick Wins view
/// (the card, the "Still fixed today" commitments, and the status label) is
/// taller than that, so its lower rows fall outside the lazily-built ListView
/// and are never created — making them unfindable. Give the tests that assert
/// on that lower content a tall surface so every row is laid out. Reset after
/// each test.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app({
  required MoodLevel? mood,
  required DateTime now,
  _FakeMoodRepository? moodRepository,
  _FakeTaskRepository? taskRepository,
}) {
  return ProviderScope(
    overrides: [
      taskRepositoryProvider
          .overrideWithValue(taskRepository ?? _FakeTaskRepository(_pending())),
      moodRepositoryProvider
          .overrideWithValue(moodRepository ?? _FakeMoodRepository(mood)),
      wearSyncServiceProvider.overrideWithValue(_FakeWearSyncService()),
      todayTimelineProvider.overrideWith((ref) async => _timeline()),
      displayNameProvider.overrideWith((ref) async => 'Bryan'),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: TodayScreen(now: now),
    ),
  );
}

/// Four low-energy candidates with distinct estimates, so both the cap and the
/// lowest-effort-first ordering are observable.
List<Task> _pending() => [
      _task('t45', 'Sort the garage shelf', 45),
      _task('t20', 'Reply to the shift email', 20),
      _task('t10', 'Refill the water bottle', 10),
      _task('t15', 'Put the laundry in', 15),
    ];

Task _task(String id, String title, int minutes) => Task(
      id: id,
      title: title,
      energy: EnergyLevel.low,
      estimatedMinutes: minutes,
      createdAt: DateTime(2026, 7, 10, 8),
    );

TodayTimelineData _timeline() {
  final flex = _task('t45', 'Sort the garage shelf', 45);
  return TodayTimelineData(
    items: [
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
        title: flex.title,
        start: DateTime(2026, 7, 10, 14),
        task: flex,
      ),
    ],
    recommendedTask: flex,
    hasCalendarPermission: true,
    lexiAvailable: false,
  );
}

class _FakeMoodRepository implements MoodRepository {
  /// Mutable so a test can change the signal and then re-derive Today, which
  /// is what a real check-in does via ref.invalidate(todayControllerProvider).
  MoodLevel? level;

  _FakeMoodRepository(this.level);

  @override
  Stream<MoodLog?> watchTodayLatest() {
    final current = level;
    return Stream.value(current == null ? null : MoodLog.create(current));
  }

  @override
  Stream<List<MoodLog>> watchRecent({int days = 14}) =>
      Stream.value(const <MoodLog>[]);

  @override
  Future<void> log(MoodLog entry) async => level = entry.level;
}

class _FakeWearSyncService extends WearSyncService {
  @override
  Future<void> pushPrimaryTask(TodayState state) async {}
}

class _FakeTaskRepository implements TaskRepository {
  List<Task> tasks;
  final completed = <String>{};

  _FakeTaskRepository(this.tasks);

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
  Future<void> markComplete(String id) async => completed.add(id);

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
  Future<Task?> getById(String id) async {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }
}
