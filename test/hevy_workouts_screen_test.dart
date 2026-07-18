import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/hevy_providers.dart';
import 'package:neuroflow/data/hevy_repository.dart';
import 'package:neuroflow/presentation/hevy_workouts_screen.dart';
import 'package:neuroflow/presentation/theme.dart';

void main() {
  testWidgets('shows a clear empty state', (tester) async {
    await _pumpWith(tester, Stream.value(const []));

    expect(find.text('Workouts'), findsOneWidget);
    expect(find.text('IMPORTED FROM HEVY'), findsOneWidget);
    expect(find.text('No imported workouts yet.'), findsOneWidget);
    expect(
      find.text('Connect Hevy and run a sync to see your workouts here.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the loading state', (tester) async {
    await _pumpWith(
      tester,
      const Stream<List<HevyWorkoutSummary>>.empty(),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows a safe error state', (tester) async {
    await _pumpWith(
      tester,
      Stream<List<HevyWorkoutSummary>>.error(
        StateError('private database details'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text("Recent workouts aren't available right now."),
      findsOneWidget,
    );
    expect(find.textContaining('private database details'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('updates when newly synced workouts arrive', (tester) async {
    final workouts = StreamController<List<HevyWorkoutSummary>>();
    addTearDown(workouts.close);
    await _pumpWith(tester, workouts.stream);

    workouts.add([_summary('Evening strength', DateTime(2026, 7, 18, 18))]);
    await tester.pump();
    expect(find.text('Evening strength'), findsOneWidget);
    expect(find.text('2 exercises\n3 sets'), findsOneWidget);
    expect(find.textContaining('60 min'), findsOneWidget);

    workouts.add([
      _summary('Morning strength', DateTime(2026, 7, 19, 8)),
      _summary('Evening strength', DateTime(2026, 7, 18, 18)),
    ]);
    await tester.pump();
    expect(find.text('Morning strength'), findsOneWidget);
    expect(find.text('Evening strength'), findsOneWidget);
  });
}

Future<void> _pumpWith(
  WidgetTester tester,
  Stream<List<HevyWorkoutSummary>> stream,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recentHevyWorkoutsProvider.overrideWith((ref) => stream),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const HevyWorkoutsScreen(),
      ),
    ),
  );
  await tester.pump();
}

HevyWorkoutSummary _summary(String title, DateTime start) => HevyWorkoutSummary(
      id: title,
      title: title,
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      exerciseCount: 2,
      setCount: 3,
    );
