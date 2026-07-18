import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/domain/health/hevy_workout.dart';
import 'package:neuroflow/platform/hevy/hevy_sync_service.dart';

/// Local, read-only cache of workouts imported from Hevy.
///
/// Each workout and all of its descendants reconcile in one transaction. A
/// malformed or failed child insert therefore cannot leave a partial workout.
class HevyRepository implements HevyWorkoutSink, HevySyncMetadataSink {
  static const metadataId = 'hevy';

  final AppDatabase _database;
  final DateTime Function() _clock;

  HevyRepository(this._database, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  @override
  Future<void> upsertWorkouts(List<HevyWorkout> workouts) async {
    for (final workout in workouts) {
      await _database.transaction(() => _replaceWorkout(workout));
    }
  }

  Future<void> _replaceWorkout(HevyWorkout workout) async {
    final oldExercises = await (_database.select(_database.hevyExercises)
          ..where((row) => row.workoutId.equals(workout.id)))
        .get();
    final oldExerciseIds = oldExercises.map((row) => row.id).toList();
    if (oldExerciseIds.isNotEmpty) {
      await (_database.delete(_database.hevySets)
            ..where((row) => row.exerciseId.isIn(oldExerciseIds)))
          .go();
    }
    await (_database.delete(_database.hevyExercises)
          ..where((row) => row.workoutId.equals(workout.id)))
        .go();

    await _database.into(_database.hevyWorkouts).insertOnConflictUpdate(
          HevyWorkoutsCompanion.insert(
            id: workout.id,
            title: workout.title,
            description: Value(workout.description),
            startTime: workout.startTime,
            endTime: workout.endTime,
            hevyUpdatedAt: Value(workout.updatedAt),
            hevyCreatedAt: Value(workout.createdAt),
            importedAt: _clock().toUtc(),
          ),
        );

    for (final exercise in workout.exercises) {
      final exerciseId = '${workout.id}:${exercise.index}';
      await _database.into(_database.hevyExercises).insert(
            HevyExercisesCompanion.insert(
              id: exerciseId,
              workoutId: workout.id,
              position: exercise.index,
              title: exercise.title,
              notes: Value(exercise.notes),
              exerciseTemplateId: exercise.exerciseTemplateId,
              supersetId: Value(exercise.supersetId),
            ),
          );
      for (final set in exercise.sets) {
        await _database.into(_database.hevySets).insert(
              HevySetsCompanion.insert(
                id: '$exerciseId:${set.index}',
                exerciseId: exerciseId,
                position: set.index,
                type: set.type,
                weightKg: Value(set.weightKg?.toDouble()),
                reps: Value(set.reps),
                distanceMeters: Value(set.distanceMeters),
                durationSeconds: Value(set.durationSeconds),
                rpe: Value(set.rpe?.toDouble()),
                customMetric: Value(set.customMetric),
                rawJson: jsonEncode(set.raw),
              ),
            );
      }
    }
  }

  Future<List<HevyWorkoutRow>> getWorkouts() =>
      (_database.select(_database.hevyWorkouts)
            ..orderBy([(row) => OrderingTerm.desc(row.startTime)]))
          .get();

  Stream<int> watchImportedWorkoutCount() =>
      _database.select(_database.hevyWorkouts).watch().map((rows) => rows.length);

  Stream<List<HevyWorkoutSummary>> watchRecentWorkouts({int limit = 10}) {
    final query = _database.customSelect(
      '''
      SELECT w.id, w.title, w.start_time, w.end_time,
             COUNT(DISTINCT e.id) AS exercise_count,
             COUNT(s.id) AS set_count
        FROM hevy_workouts w
        LEFT JOIN hevy_exercises e ON e.workout_id = w.id
        LEFT JOIN hevy_sets s ON s.exercise_id = e.id
       GROUP BY w.id
       ORDER BY w.start_time DESC
       LIMIT ?
      ''',
      variables: [Variable.withInt(limit)],
      readsFrom: {
        _database.hevyWorkouts,
        _database.hevyExercises,
        _database.hevySets,
      },
    );
    return query.watch().map(
          (rows) => rows
              .map(HevyWorkoutSummary.tryFromRow)
              .whereType<HevyWorkoutSummary>()
              .toList(growable: false),
        );
  }

  Future<HevySyncMetadataRow?> getSyncMetadata() =>
      (_database.select(_database.hevySyncMetadata)
            ..where((row) => row.id.equals(metadataId)))
          .getSingleOrNull();

  @override
  Future<void> recordSyncStarted(DateTime at) =>
      _database.into(_database.hevySyncMetadata).insertOnConflictUpdate(
            HevySyncMetadataCompanion.insert(
              id: metadataId,
              lastAttemptAt: Value(at.toUtc()),
              lastError: const Value(null),
            ),
          );

  @override
  Future<void> recordSyncSucceeded(DateTime at, int imported) async {
    await (_database.update(_database.hevySyncMetadata)
          ..where((row) => row.id.equals(metadataId)))
        .write(HevySyncMetadataCompanion(
      lastAttemptAt: Value(at.toUtc()),
      lastSuccessAt: Value(at.toUtc()),
      lastError: const Value(null),
      lastImportedCount: Value(imported),
    ));
  }

  @override
  Future<void> recordSyncFailed(DateTime at, Object error) =>
      _database.into(_database.hevySyncMetadata).insertOnConflictUpdate(
            HevySyncMetadataCompanion.insert(
              id: metadataId,
              lastAttemptAt: Value(at.toUtc()),
              lastError: Value(error.runtimeType.toString()),
            ),
          );
}

class HevyWorkoutSummary {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final int exerciseCount;
  final int setCount;

  const HevyWorkoutSummary({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.exerciseCount,
    required this.setCount,
  });

  Duration get duration {
    final value = endTime.difference(startTime);
    return value.isNegative ? Duration.zero : value;
  }

  static HevyWorkoutSummary? tryFromRow(QueryRow row) {
    try {
      final id = row.read<String>('id');
      final title = row.read<String>('title').trim();
      final start = row.read<DateTime>('start_time');
      final end = row.read<DateTime>('end_time');
      if (id.isEmpty || title.isEmpty) return null;
      return HevyWorkoutSummary(
        id: id,
        title: title,
        startTime: start,
        endTime: end,
        exerciseCount: row.read<int>('exercise_count'),
        setCount: row.read<int>('set_count'),
      );
    } on Object {
      // A damaged individual cache row should not prevent the rest rendering.
      return null;
    }
  }
}
