import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/data/routine_repository_impl.dart';
import 'package:neuroflow/domain/routine.dart';

void main() {
  test('saving a routine persists its ordered checklist steps', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = DriftRoutineRepository(database);
    final routine = Routine.create(
      name: 'Get ready for work',
      anchor: RoutineAnchor.custom,
      scheduleHour: 5,
      scheduleMinute: 0,
    );
    final completeRoutine = routine.copyWith(
      steps: [
        RoutineStep.create(
          routineId: routine.id,
          position: 0,
          title: 'Brush teeth',
        ),
        RoutineStep.create(
          routineId: routine.id,
          position: 1,
          title: 'Leave for work by 5:45 AM',
        ),
      ],
    );

    await repository.save(completeRoutine);
    final saved = await repository.watchActive().first;

    expect(saved, hasLength(1));
    expect(saved.single.name, 'Get ready for work');
    expect(saved.single.scheduleHour, 5);
    expect(saved.single.scheduleMinute, 0);
    expect(saved.single.steps.map((step) => step.title), [
      'Brush teeth',
      'Leave for work by 5:45 AM',
    ]);

    await database.close();
  });
}
