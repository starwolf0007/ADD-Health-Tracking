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

    expect(
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
}
