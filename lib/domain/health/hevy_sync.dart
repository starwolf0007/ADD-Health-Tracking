import 'package:neuroflow/domain/health/hevy_workout.dart';

/// Destination boundary for imported workouts.
///
/// Lives in the domain layer so the Drift-backed repository (data) and the
/// sync service (platform) can both depend on it without the data layer
/// importing platform code. Upserts must be idempotent using Hevy's workout
/// ID.
abstract interface class HevyWorkoutSink {
  Future<void> upsertWorkouts(List<HevyWorkout> workouts);
}

abstract interface class HevySyncMetadataSink {
  Future<void> recordSyncStarted(DateTime at);
  Future<void> recordSyncSucceeded(DateTime at, int imported);
  Future<void> recordSyncFailed(DateTime at, Object error);
}
