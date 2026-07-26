import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:neuroflow/platform/hevy/hevy_api_client.dart';
import 'package:neuroflow/platform/hevy/hevy_credentials_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'integration.hevy.api_key': 'test-key',
    });
  });

  test('sends api-key header and parses workout count', () async {
    final httpClient = MockClient((request) async {
      expect(request.headers['api-key'], 'test-key');
      expect(request.url.path, '/v1/workouts/count');
      return http.Response('{"workout_count":42}', 200);
    });

    final client = HevyApiClient(
      httpClient: httpClient,
      credentials: const HevyCredentialsStore(FlutterSecureStorage()),
    );

    expect(await client.getWorkoutCount(), 42);
  });

  test('does not leak response body in authentication errors', () async {
    final httpClient = MockClient((request) async {
      return http.Response('secret server details', 401);
    });

    final client = HevyApiClient(
      httpClient: httpClient,
      credentials: const HevyCredentialsStore(FlutterSecureStorage()),
    );

    await expectLater(
      () => client.getWorkoutCount(),
      throwsA(
        isA<HevyApiException>().having(
          (error) => error.message,
          'message',
          'Hevy rejected the API key.',
        ),
      ),
    );
  });

  test('wraps malformed 2xx bodies in HevyApiException', () async {
    final httpClient = MockClient((request) async {
      return http.Response('not json', 200);
    });

    final client = HevyApiClient(
      httpClient: httpClient,
      credentials: const HevyCredentialsStore(FlutterSecureStorage()),
    );

    await expectLater(
      () => client.getWorkoutCount(),
      throwsA(
        isA<HevyApiException>().having(
          (error) => error.message,
          'message',
          'Hevy returned an unexpected response format.',
        ),
      ),
    );
  });

  test('rejects workout pages with missing pagination metadata', () async {
    final httpClient = MockClient((request) async {
      return http.Response('{"workouts":[]}', 200);
    });

    final client = HevyApiClient(
      httpClient: httpClient,
      credentials: const HevyCredentialsStore(FlutterSecureStorage()),
    );

    await expectLater(
      () => client.getWorkouts(),
      throwsA(isA<FormatException>()),
    );
  });

  test('parses a valid empty first page', () async {
    final httpClient = MockClient((request) async {
      return http.Response('{"page":1,"page_count":1,"workouts":[]}', 200);
    });

    final client = HevyApiClient(
      httpClient: httpClient,
      credentials: const HevyCredentialsStore(FlutterSecureStorage()),
    );

    final page = await client.getWorkouts();
    expect(page.workouts, isEmpty);
    expect(page.hasNextPage, isFalse);
  });

  test('parses numeric custom metrics and current superset identifiers',
      () async {
    final httpClient = MockClient((request) async {
      return http.Response(
        '''
        {
          "page": 1,
          "page_count": 1,
          "workouts": [
            {
              "id": "workout-1",
              "title": "Stair workout",
              "start_time": "2026-07-25T08:00:00Z",
              "end_time": "2026-07-25T08:30:00Z",
              "exercises": [
                {
                  "index": 0,
                  "title": "Stair Machine",
                  "exercise_template_id": "template-1",
                  "supersets_id": 7,
                  "sets": [
                    {
                      "index": 0,
                      "type": "normal",
                      "custom_metric": 50
                    }
                  ]
                }
              ]
            }
          ]
        }
        ''',
        200,
      );
    });

    final client = HevyApiClient(
      httpClient: httpClient,
      credentials: const HevyCredentialsStore(FlutterSecureStorage()),
    );

    final workout = (await client.getWorkouts()).workouts.single;
    expect(workout.exercises.single.supersetId, '7');
    expect(workout.exercises.single.sets.single.customMetric, 50);
  });
}
