// lib/data/routine_repository_impl.dart
//
// Drift-backed RoutineRepository. Joins Routines + RoutineSteps
// and assembles domain Routine objects with their steps list.

import 'package:drift/drift.dart';

import '../domain/routine.dart';
import 'database.dart';
import 'routine_repository.dart';

class DriftRoutineRepository implements RoutineRepository {
  final AppDatabase _db;

  DriftRoutineRepository(this._db);

  // ------------------------------------------------------------------
  // Mappers
  // ------------------------------------------------------------------

  Routine _rowsToRoutine(RoutineRow row, List<RoutineStepRow> stepRows) {
    return Routine(
      id: row.id,
      name: row.name,
      anchor: _anchorFromString(row.anchor),
      scheduleHour: row.scheduleHour,
      scheduleMinute: row.scheduleMinute,
      isActive: row.isActive,
      steps: stepRows.map(_stepRowToStep).toList(),
      createdAt: row.createdAt,
    );
  }

  RoutineStep _stepRowToStep(RoutineStepRow row) {
    return RoutineStep(
      id: row.id,
      routineId: row.routineId,
      position: row.position,
      title: row.title,
      notes: row.notes,
      durationMinutes: row.durationMinutes,
      isComplete: row.isComplete,
    );
  }

  RoutinesCompanion _routineToCompanion(Routine r) {
    return RoutinesCompanion(
      id: Value(r.id),
      name: Value(r.name),
      anchor: Value(_anchorToString(r.anchor)),
      scheduleHour: Value(r.scheduleHour),
      scheduleMinute: Value(r.scheduleMinute),
      isActive: Value(r.isActive),
      createdAt: Value(r.createdAt),
    );
  }

  RoutineStepsCompanion _stepToCompanion(RoutineStep s) {
    return RoutineStepsCompanion(
      id: Value(s.id),
      routineId: Value(s.routineId),
      position: Value(s.position),
      title: Value(s.title),
      notes: Value(s.notes),
      durationMinutes: Value(s.durationMinutes),
      isComplete: Value(s.isComplete),
    );
  }

  // ------------------------------------------------------------------
  // Interface
  // ------------------------------------------------------------------

  @override
  Stream<List<Routine>> watchActive() {
    return _db.watchActiveRoutines().asyncMap((rows) async {
      final result = <Routine>[];
      for (final row in rows) {
        final steps = await _db.fetchStepsForRoutine(row.id);
        result.add(_rowsToRoutine(row, steps));
      }
      return result;
    });
  }

  @override
  Future<List<Routine>> fetchDueNow() async {
    final now = DateTime.now();
    final allRows = await _db.watchActiveRoutines().first;
    final result = <Routine>[];
    for (final row in allRows) {
      final anchor = _anchorFromString(row.anchor);
      if (_isDueNow(anchor, row.scheduleHour, row.scheduleMinute, now)) {
        final steps = await _db.fetchStepsForRoutine(row.id);
        final routine = _rowsToRoutine(row, steps);
        // Don't surface a routine that's already fully complete today.
        if (!routine.isComplete) {
          result.add(routine);
        }
      }
    }
    return result;
  }

  @override
  Future<void> save(Routine routine) async {
    await _db.upsertRoutine(_routineToCompanion(routine));
    for (final step in routine.steps) {
      await _db.upsertStep(_stepToCompanion(step));
    }
  }

  @override
  Future<void> updateStep(RoutineStep step) async {
    await _db.markStepComplete(step.id, step.isComplete);
  }

  @override
  Future<void> resetRoutine(String routineId) async {
    await _db.resetRoutineSteps(routineId);
  }

  @override
  Future<void> delete(String routineId) async {
    await _db.deleteRoutine(routineId);
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  bool _isDueNow(RoutineAnchor anchor, int? hour, int? minute, DateTime now) {
    final h = now.hour;
    switch (anchor) {
      case RoutineAnchor.morning:
        return h >= 5 && h < 10;
      case RoutineAnchor.midday:
        return h >= 11 && h < 14;
      case RoutineAnchor.evening:
        return h >= 17 && h < 21;
      case RoutineAnchor.custom:
        if (hour == null || minute == null) return false;
        return now.hour == hour && (now.minute - minute).abs() <= 30;
    }
  }

  RoutineAnchor _anchorFromString(String s) {
    switch (s) {
      case 'morning':
        return RoutineAnchor.morning;
      case 'midday':
        return RoutineAnchor.midday;
      case 'evening':
        return RoutineAnchor.evening;
      default:
        return RoutineAnchor.custom;
    }
  }

  String _anchorToString(RoutineAnchor a) {
    switch (a) {
      case RoutineAnchor.morning:
        return 'morning';
      case RoutineAnchor.midday:
        return 'midday';
      case RoutineAnchor.evening:
        return 'evening';
      case RoutineAnchor.custom:
        return 'custom';
    }
  }
}
