import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/data/routine_repository.dart';
import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/presentation/routine_screen.dart';
import 'package:neuroflow/presentation/theme.dart';

void main() {
  testWidgets('a completed routine step persists before advancing',
      (tester) async {
    final repository = _RoutineRepository();
    await tester.pumpWidget(_app(repository));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(repository.updatedSteps, hasLength(1));
    expect(repository.updatedSteps.single.id, 'step-1');
    expect(find.text('Take medicine'), findsOneWidget);
  });

  testWidgets('a failed routine-step save restores the step and explains why',
      (tester) async {
    final repository = _RoutineRepository(shouldFail: true);
    await tester.pumpWidget(_app(repository));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Brush teeth'), findsOneWidget);
    expect(find.text('Could not save that step. Try again.'), findsOneWidget);
  });
}

Widget _app(RoutineRepository repository) {
  final routine = Routine(
    id: 'routine-1',
    name: 'Get ready for work',
    anchor: RoutineAnchor.custom,
    scheduleHour: 5,
    scheduleMinute: 15,
    isActive: true,
    activeDays: '12345',
    steps: [
      RoutineStep(
        id: 'step-1',
        routineId: 'routine-1',
        position: 0,
        title: 'Brush teeth',
      ),
      RoutineStep(
        id: 'step-2',
        routineId: 'routine-1',
        position: 1,
        title: 'Take medicine',
      ),
    ],
    createdAt: DateTime(2026, 7, 12),
  );

  return ProviderScope(
    overrides: [routineRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: RoutineScreen(routine: routine, onFinished: () {}),
    ),
  );
}

class _RoutineRepository implements RoutineRepository {
  _RoutineRepository({this.shouldFail = false});

  final bool shouldFail;
  final List<RoutineStep> updatedSteps = [];

  @override
  Future<void> updateStep(RoutineStep step) async {
    if (shouldFail) throw StateError('Storage unavailable');
    updatedSteps.add(step);
  }

  @override
  Stream<List<Routine>> watchActive() => Stream.value(const []);

  @override
  Future<List<Routine>> fetchDueNow() async => const [];

  @override
  Future<void> save(Routine routine) async {}

  @override
  Future<void> resetRoutine(String routineId) async {}

  @override
  Future<void> delete(String routineId) async {}
}
