// test/presentation/mood_check_in_test.dart
//
// The check-in is the Quick Wins entry signal (spec §6), so what it writes and
// what it refuses to display are both load-bearing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/mood.dart';
import 'package:neuroflow/domain/mood_repository.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/widgets/mood_check_in.dart';

void main() {
  testWidgets('prompts when nothing has been logged today', (tester) async {
    await _pump(tester, FakeMoodRepository());

    expect(find.text("HOW'S TODAY GOING?"), findsOneWidget);
    for (final level in MoodLevel.values) {
      expect(find.byKey(Key('moodChip_${level.name}')), findsOneWidget);
    }
  });

  testWidgets('offers every level by its label, never a score', (tester) async {
    await _pump(tester, FakeMoodRepository());

    // §13: the 1..5 score is storage only and must never reach the screen.
    for (final level in MoodLevel.values) {
      expect(find.text(level.label), findsOneWidget);
      expect(find.text('${level.score}'), findsNothing);
    }
  });

  testWidgets('tapping a level logs that check-in', (tester) async {
    final repository = FakeMoodRepository();
    await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('moodChip_low')));
    await tester.pumpAndSettle();

    expect(repository.logged, hasLength(1));
    expect(repository.logged.single.level, MoodLevel.low);
  });

  testWidgets('collapses to a summary once a mood exists', (tester) async {
    await _pump(
      tester,
      FakeMoodRepository(initial: MoodLog.create(MoodLevel.veryLow)),
    );

    expect(find.byKey(const Key('moodSummary')), findsOneWidget);
    expect(find.text('Checked in · Rough'), findsOneWidget);
    expect(find.text("HOW'S TODAY GOING?"), findsNothing);
  });

  testWidgets('collapses after logging', (tester) async {
    final repository = FakeMoodRepository();
    await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('moodChip_great')));
    await tester.pumpAndSettle();

    expect(find.text('Checked in · Great'), findsOneWidget);
  });

  testWidgets('the summary reopens so a check-in can be revised',
      (tester) async {
    // §6 exits Quick Wins when a better check-in lands, so revising has to
    // stay reachable all day.
    final repository =
        FakeMoodRepository(initial: MoodLog.create(MoodLevel.veryLow));
    await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('moodSummary')));
    await tester.pumpAndSettle();
    expect(find.text("HOW'S TODAY GOING?"), findsOneWidget);

    await tester.tap(find.byKey(const Key('moodChip_good')));
    await tester.pumpAndSettle();

    expect(repository.logged.single.level, MoodLevel.good);
    expect(find.text('Checked in · Good'), findsOneWidget);
  });

  testWidgets('renders nothing while the check-in is still loading',
      (tester) async {
    await _pump(tester, FakeMoodRepository(), emitInitial: false);

    expect(find.text("HOW'S TODAY GOING?"), findsNothing);
    expect(find.byKey(const Key('moodSummary')), findsNothing);
  });

  testWidgets('a failed write surfaces an error and keeps the prompt',
      (tester) async {
    final repository = FakeMoodRepository()..failWith = Exception('offline');
    await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('moodChip_low')));
    await tester.pumpAndSettle();

    expect(find.text('Could not save your check-in.'), findsOneWidget);
    expect(find.text("HOW'S TODAY GOING?"), findsOneWidget);
  });

  testWidgets('a read failure hides the strip rather than blocking Today',
      (tester) async {
    await _pump(tester, FakeMoodRepository(readError: Exception('db gone')));

    expect(find.text("HOW'S TODAY GOING?"), findsNothing);
    expect(find.byKey(const Key('moodSummary')), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeMoodRepository repository, {
  bool emitInitial = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        moodRepositoryProvider.overrideWithValue(repository),
        if (!emitInitial)
          todayMoodProvider.overrideWith((ref) => Stream<MoodLog?>.empty()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: MoodCheckInStrip()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class FakeMoodRepository implements MoodRepository {
  FakeMoodRepository({MoodLog? initial, this.readError}) : _latest = initial;

  final Object? readError;
  Object? failWith;
  final List<MoodLog> logged = [];

  MoodLog? _latest;
  final StreamController<MoodLog?> _changes =
      StreamController<MoodLog?>.broadcast();

  @override
  Stream<MoodLog?> watchTodayLatest() async* {
    if (readError != null) throw readError!;
    yield _latest;
    yield* _changes.stream;
  }

  @override
  Future<void> log(MoodLog entry) async {
    if (failWith != null) throw failWith!;
    logged.add(entry);
    _latest = entry;
    _changes.add(entry);
  }
}
