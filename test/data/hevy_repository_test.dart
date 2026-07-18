import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/data/hevy_repository.dart';
import 'package:neuroflow/domain/health/hevy_workout.dart';
import 'package:neuroflow/platform/hevy/hevy_api_client.dart';
import 'package:neuroflow/platform/hevy/hevy_credentials_store.dart';
import 'package:neuroflow/platform/hevy/hevy_sync_service.dart';

void main() {
  late AppDatabase database;
  late HevyRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = HevyRepository(
      database,
      clock: () => DateTime.utc(2026, 7, 18),
    );
    FlutterSecureStorage.setMockInitialValues({
      'integration.hevy.api_key': 'test-key',
    });
  });

  tearDown(() => database.close());

  test('first import inserts normalized workout data', () async {
    await repository.upsertWorkouts([_workout()]);

    expect(await database.select(database.hevyWorkouts).get(), hasLength(1));
    expect(await database.select(database.hevyExercises).get(), hasLength(1));
    expect(await database.select(database.hevySets).get(), hasLength(2));
  });

  test('repeated import creates no duplicates', () async {
    await repository.upsertWorkouts([_workout()]);
    await repository.upsertWorkouts([_workout()]);

    expect(await database.select(database.hevyWorkouts).get(), hasLength(1));
    expect(await database.select(database.hevyExercises).get(), hasLength(1));
    expect(await database.select(database.hevySets).get(), hasLength(2));
  });

  test('recent summaries include child counts in newest-first order', () async {
    await repository.upsertWorkouts([
      _workout(),
      HevyWorkout(
        id: 'workout-2',
        title: 'Later workout',
        startTime: DateTime.utc(2026, 7, 19, 8),
        endTime: DateTime.utc(2026, 7, 19, 8, 30),
        exercises: [
          _exercise(sets: [_set(0, reps: 5)])
        ],
      ),
    ]);

    final summaries = await repository.watchRecentWorkouts().first;
    expect(summaries.map((item) => item.title),
        ['Later workout', 'Morning workout']);
    expect(summaries.first.exerciseCount, 1);
    expect(summaries.first.setCount, 1);
    expect(summaries.first.duration, const Duration(minutes: 30));
  });

  test('changed workout reconciles child records', () async {
    await repository.upsertWorkouts([_workout()]);
    await repository.upsertWorkouts([
      _workout(
        title: 'Changed',
        exercises: [
          _exercise(index: 1, title: 'Deadlift', sets: [_set(0, reps: 3)]),
        ],
      ),
    ]);

    final workouts = await database.select(database.hevyWorkouts).get();
    final exercises = await database.select(database.hevyExercises).get();
    final sets = await database.select(database.hevySets).get();
    expect(workouts.single.title, 'Changed');
    expect(exercises.single.title, 'Deadlift');
    expect(exercises.single.position, 1);
    expect(sets.single.reps, 3);
  });

  test('failed workout transaction rolls back completely', () async {
    await repository.upsertWorkouts([_workout()]);
    await database.customStatement('''
      CREATE TRIGGER reject_hevy_set BEFORE INSERT ON hevy_sets
      BEGIN SELECT RAISE(FAIL, 'set rejected'); END
    ''');

    await expectLater(
      repository.upsertWorkouts([_workout(title: 'Must not persist')]),
      throwsA(anything),
    );

    final workouts = await database.select(database.hevyWorkouts).get();
    expect(workouts.single.title, 'Morning workout');
    expect(await database.select(database.hevyExercises).get(), hasLength(1));
    expect(await database.select(database.hevySets).get(), hasLength(2));
  });

  test('cached workouts survive sync failure', () async {
    await repository.upsertWorkouts([_workout()]);
    final client = HevyApiClient(
      httpClient: MockClient((_) async => http.Response('unavailable', 503)),
      credentials: const HevyCredentialsStore(FlutterSecureStorage()),
    );
    final service = HevySyncService(
      api: client,
      sink: repository,
      metadata: repository,
      clock: () => DateTime.utc(2026, 7, 19),
    );

    await expectLater(service.importAll(), throwsA(isA<HevyApiException>()));

    expect(await repository.getWorkouts(), hasLength(1));
    final metadata = await repository.getSyncMetadata();
    expect(
      metadata?.lastAttemptAt?.millisecondsSinceEpoch,
      DateTime.utc(2026, 7, 19).millisecondsSinceEpoch,
    );
    expect(metadata?.lastSuccessAt, isNull);
    expect(metadata?.lastError, 'HevyApiException');
  });
}

HevyWorkout _workout({
  String title = 'Morning workout',
  List<HevyExercise>? exercises,
}) =>
    HevyWorkout(
      id: 'workout-1',
      title: title,
      startTime: DateTime.utc(2026, 7, 18, 8),
      endTime: DateTime.utc(2026, 7, 18, 9),
      exercises: exercises ??
          [
            _exercise(sets: [_set(0, reps: 10), _set(1, reps: 8)])
          ],
    );

HevyExercise _exercise({
  int index = 0,
  String title = 'Squat',
  List<HevySet> sets = const [],
}) =>
    HevyExercise(
      index: index,
      title: title,
      exerciseTemplateId: 'template-$index',
      sets: sets,
    );

HevySet _set(int index, {int? reps}) => HevySet(
      index: index,
      type: 'normal',
      reps: reps,
      raw: {'index': index, 'type': 'normal', 'reps': reps},
    );
