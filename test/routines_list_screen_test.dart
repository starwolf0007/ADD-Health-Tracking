import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/data/routine_repository.dart';
import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/presentation/routines_list_screen.dart';
import 'package:neuroflow/presentation/theme.dart';

void main() {
  testWidgets('routine save includes typed steps and supports reordering',
      (tester) async {
    tester.view.physicalSize = const Size(1344, 2992);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeRoutineRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [routineRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const RoutinesListScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Add routine'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Routine name'),
      'Get ready for work',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a step'),
      'Brush teeth',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a step'),
      'Take medicine',
    );
    await tester.tap(find.byTooltip('Add step'));
    await tester.pump();
    await tester.tap(find.byTooltip('Move step down').first);
    await tester.pump();

    // The keyboard Done action adds the step, and the primary Save action is
    // still visible without scrolling the whole sheet to the bottom.
    await tester.tap(find.byKey(const ValueKey('routine-save-top')));
    await tester.pumpAndSettle();

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.name, 'Get ready for work');
    expect(repository.saved.single.steps.map((step) => step.title), [
      'Take medicine',
      'Brush teeth',
    ]);
  });

  testWidgets('pending step remains visible when routine name is missing',
      (tester) async {
    tester.view.physicalSize = const Size(1344, 2992);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routineRepositoryProvider.overrideWithValue(_FakeRoutineRepository())
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const RoutinesListScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Add routine'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a step'),
      'Take medicine',
    );

    await tester.tap(find.byKey(const ValueKey('routine-save-top')));
    await tester.pump();

    expect(find.text('Take medicine'), findsOneWidget);
    expect(
        find.text('Add a routine name and at least one step.'), findsOneWidget);
  });
}

class _FakeRoutineRepository implements RoutineRepository {
  final List<Routine> saved = [];

  @override
  Stream<List<Routine>> watchActive() => Stream.value(saved);

  @override
  Future<List<Routine>> fetchDueNow() async => const [];

  @override
  Future<void> save(Routine routine) async => saved.add(routine);

  @override
  Future<void> updateStep(RoutineStep step) async {}

  @override
  Future<void> resetRoutine(String routineId) async {}

  @override
  Future<void> delete(String routineId) async {}
}
