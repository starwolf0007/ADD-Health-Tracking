import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/data/task_repository.dart';
import 'package:neuroflow/domain/mood.dart';
import 'package:neuroflow/domain/mood_repository.dart';
import 'package:neuroflow/domain/reentry_note.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/platform/wear/wear_sync_service.dart';
import 'package:neuroflow/presentation/reflect_screen.dart';
import 'package:neuroflow/presentation/theme.dart';

void main() {
  testWidgets('a rough check-in does not promise Quick Wins with no tasks',
      (tester) async {
    final moods = _FakeMoodRepository();
    addTearDown(moods.dispose);

    await tester.pumpWidget(_app(moods: moods, tasks: const []));
    await tester.pump(const Duration(milliseconds: 200));

    await _logRough(tester);

    expect(
      find.text('Logged Rough. Nothing is pending right now.'),
      findsOneWidget,
    );
    expect(find.text('Quick Wins'), findsNothing);
  });

  testWidgets('a rough check-in promises Quick Wins when a win is pending',
      (tester) async {
    final moods = _FakeMoodRepository();
    addTearDown(moods.dispose);
    final task = Task(
      id: 'pending',
      title: 'Put the cup away',
      energy: EnergyLevel.low,
      estimatedMinutes: 2,
      createdAt: DateTime(2026, 8, 1, 9),
    );

    await tester.pumpWidget(_app(moods: moods, tasks: [task]));
    await tester.pump(const Duration(milliseconds: 200));

    await _logRough(tester);

    expect(
      find.text('Logged Rough. Today will lean toward Quick Wins.'),
      findsOneWidget,
    );
    expect(find.text('Quick Wins'), findsOneWidget);
  });
}

Future<void> _logRough(WidgetTester tester) async {
  await tester.tap(find.text('Rough'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Skip'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Widget _app({
  required _FakeMoodRepository moods,
  required List<Task> tasks,
}) {
  return ProviderScope(
    overrides: [
      moodRepositoryProvider.overrideWithValue(moods),
      taskRepositoryProvider.overrideWithValue(_FakeTaskRepository(tasks)),
      wearSyncServiceProvider.overrideWithValue(_FakeWearSyncService()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const ReflectScreen(),
    ),
  );
}

class _FakeMoodRepository implements MoodRepository {
  final _today = StreamController<MoodLog?>.broadcast();
  final _recent = StreamController<List<MoodLog>>.broadcast();
  MoodLog? latest;

  @override
  Stream<MoodLog?> watchTodayLatest() async* {
    yield latest;
    yield* _today.stream;
  }

  @override
  Stream<List<MoodLog>> watchRecent({int days = 14}) async* {
    yield latest == null ? const [] : [latest!];
    yield* _recent.stream;
  }

  @override
  Future<void> log(MoodLog entry) async {
    latest = entry;
    _today.add(entry);
    _recent.add([entry]);
  }

  Future<void> dispose() async {
    await _today.close();
    await _recent.close();
  }
}

class _FakeWearSyncService extends WearSyncService {
  @override
  Future<void> pushPrimaryTask(TodayState state) async {}
}

class _FakeTaskRepository implements TaskRepository {
  final List<Task> tasks;

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
  Future<Task?> getById(String id) async =>
      tasks.where((task) => task.id == id).firstOrNull;
}
