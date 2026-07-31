import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/widgets/due_routines_card.dart';

Routine _routine({
  required String id,
  required String name,
  List<RoutineStep> steps = const [],
}) {
  return Routine(
    id: id,
    name: name,
    anchor: RoutineAnchor.morning,
    steps: steps,
    createdAt: DateTime(2026, 1, 1),
  );
}

Widget _harness(List<Routine> due) {
  return ProviderScope(
    overrides: [
      dueRoutinesProvider.overrideWith((ref) async => due),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: DueRoutinesCard()),
    ),
  );
}

void main() {
  testWidgets('empty due list renders nothing',
      (tester) async {
    await tester.pumpWidget(_harness(const []));
    await tester.pumpAndSettle();

    expect(find.text('Start'), findsNothing);
    expect(find.text('Routine'), findsNothing);
  });

  testWidgets('one due routine shows name and Start',
      (tester) async {
    final routine = _routine(
      id: 'r1',
      name: 'Morning reset',
      steps: [
        RoutineStep(
          id: 's1',
          routineId: 'r1',
          position: 0,
          title: 'Drink water',
        ),
      ],
    );

    await tester.pumpWidget(_harness([routine]));
    await tester.pumpAndSettle();

    expect(find.text('Morning reset'), findsOneWidget);
    expect(find.text('Next: Drink water'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.byKey(const ValueKey('due-routine-r1')), findsOneWidget);
  });

  testWidgets('caps at two routines when more are due',
      (tester) async {
    final routines = [
      for (var i = 1; i <= 3; i++)
        _routine(id: 'r$i', name: 'Routine $i'),
    ];

    await tester.pumpWidget(_harness(routines));
    await tester.pumpAndSettle();

    expect(find.text('Routine 1'), findsOneWidget);
    expect(find.text('Routine 2'), findsOneWidget);
    expect(find.text('Routine 3'), findsNothing);
    expect(find.text('Start'), findsNWidgets(2));
  });

  testWidgets('ready copy when no incomplete step',
      (tester) async {
    final routine = _routine(id: 'r-empty', name: 'Evening wind-down');

    await tester.pumpWidget(_harness([routine]));
    await tester.pumpAndSettle();

    expect(find.text('Ready when you are'), findsOneWidget);
  });
}
