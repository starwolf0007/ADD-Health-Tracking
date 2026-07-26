// lib/data/routine_seeds.dart
//
// Preset routines. Seeded on first launch — user can edit or delete any of them.
// Chosen for ADHD: short, achievable, ordered by energy cost (lowest first).

import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/data/routine_repository.dart';

/// Call once during onboarding or first launch.
/// Safe to call on every startup — no-ops if routines with these names already exist.
Future<void> seedDefaultRoutines(RoutineRepository repo) async {
  final existing = await repo.watchActive().first;
  final existingNames = existing.map((r) => r.name).toSet();

  if (!existingNames.contains('Morning start')) {
    final morningRoutine = Routine.create(
      name: 'Morning start',
      anchor: RoutineAnchor.morning,
      steps: [], // built below with proper routineId
    );

    final morningSteps = [
      RoutineStep.create(
        routineId: morningRoutine.id,
        position: 0,
        title: 'Drink a glass of water',
        durationMinutes: 1,
      ),
      RoutineStep.create(
        routineId: morningRoutine.id,
        position: 1,
        title: 'Open curtains or go outside for 2 minutes',
        notes: 'Light exposure resets your body clock',
        durationMinutes: 2,
      ),
      RoutineStep.create(
        routineId: morningRoutine.id,
        position: 2,
        title: 'Check NeuroFlow — what\'s the one thing today?',
        durationMinutes: 2,
      ),
      RoutineStep.create(
        routineId: morningRoutine.id,
        position: 3,
        title: 'Eat something — even small',
        durationMinutes: 10,
      ),
    ];

    final morningWithSteps = morningRoutine.copyWith(steps: morningSteps);
    await repo.save(morningWithSteps);
  }

  // ------------------------------------------------------------------

  if (!existingNames.contains('Wind down')) {
    final eveningRoutine = Routine.create(
      name: 'Wind down',
      anchor: RoutineAnchor.evening,
      steps: [],
    );

    final eveningSteps = [
      RoutineStep.create(
        routineId: eveningRoutine.id,
        position: 0,
        title: 'Mark today\'s tasks done or carry forward',
        durationMinutes: 3,
      ),
      RoutineStep.create(
        routineId: eveningRoutine.id,
        position: 1,
        title: 'Set one intention for tomorrow',
        notes: 'Just one — keep it simple',
        durationMinutes: 2,
      ),
      RoutineStep.create(
        routineId: eveningRoutine.id,
        position: 2,
        title: 'Phone face-down or on charger',
        durationMinutes: 1,
      ),
    ];

    final eveningWithSteps = eveningRoutine.copyWith(steps: eveningSteps);
    await repo.save(eveningWithSteps);
  }
}
