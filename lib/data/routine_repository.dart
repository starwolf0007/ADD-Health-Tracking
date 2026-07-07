// lib/data/routine_repository.dart
//
// Abstract repository for Routine CRUD.
// Executive layer and Presentation layer depend only on this interface.

import 'package:neuroflow/domain/routine.dart';

abstract class RoutineRepository {
  /// All active routines, ordered by anchor then name.
  Stream<List<Routine>> watchActive();

  /// Routines that are due right now based on current time-of-day.
  Future<List<Routine>> fetchDueNow();

  Future<void> save(Routine routine);
  Future<void> updateStep(RoutineStep step);
  Future<void> resetRoutine(String routineId); // marks all steps incomplete
  Future<void> delete(String routineId);
}
