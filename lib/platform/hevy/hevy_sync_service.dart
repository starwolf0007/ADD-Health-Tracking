import 'package:neuroflow/domain/health/hevy_workout.dart';
import 'package:neuroflow/platform/hevy/hevy_api_client.dart';

/// Destination boundary for imported workouts.
///
/// A Drift implementation can be added without making the API client depend on
/// local persistence. Upserts must be idempotent using Hevy's workout ID.
abstract interface class HevyWorkoutSink {
  Future<void> upsertWorkouts(List<HevyWorkout> workouts);
}

class HevySyncResult {
  final int imported;
  final int pagesFetched;

  const HevySyncResult({
    required this.imported,
    required this.pagesFetched,
  });
}

/// Initial full import.
///
/// Incremental event sync (`GET /v1/workouts/events`) should be added after the
/// local schema and deletion policy have been reviewed and tested.
class HevySyncService {
  final HevyApiClient _api;
  final HevyWorkoutSink _sink;

  const HevySyncService({
    required HevyApiClient api,
    required HevyWorkoutSink sink,
  })  : _api = api,
        _sink = sink;

  Future<HevySyncResult> importAll({
    int pageSize = 10,
  }) async {
    var page = 1;
    var imported = 0;
    var pagesFetched = 0;

    while (true) {
      final result = await _api.getWorkouts(
        page: page,
        pageSize: pageSize,
      );

      await _sink.upsertWorkouts(result.workouts);
      imported += result.workouts.length;
      pagesFetched += 1;

      if (!result.hasNextPage) break;
      page += 1;
    }

    return HevySyncResult(
      imported: imported,
      pagesFetched: pagesFetched,
    );
  }
}
