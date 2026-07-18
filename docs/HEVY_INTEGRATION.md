# Hevy integration — read-only foundation

## Scope

This first slice intentionally supports read-only access:

- Securely save and clear the user's Hevy API key.
- Verify the key with `GET /v1/user/info`.
- Read workout count.
- Read paginated workouts.
- Read a single workout.
- Import all workouts through a persistence boundary.

It does **not** write or update workouts in Hevy.

## Security rules

- Store the API key only in `flutter_secure_storage`.
- Never place the key in Drift, logs, exceptions, analytics, screenshots,
  source control, or build-time environment files.
- Never include Hevy response bodies in user-facing authentication errors.
- Disconnecting Hevy must clear the secure-storage entry.

## API details

- Base URL: `https://api.hevyapp.com/v1`
- Authentication header: `api-key`
- Hevy API access currently requires Hevy Pro.
- Generate a key in Hevy's web developer settings.

## Composition-root wiring

Add these providers to `lib/app/providers.dart`:

```dart
import 'package:http/http.dart' as http;
import 'package:neuroflow/platform/hevy/hevy_api_client.dart';
import 'package:neuroflow/platform/hevy/hevy_credentials_store.dart';

final hevyCredentialsStoreProvider = Provider<HevyCredentialsStore>((ref) {
  return const HevyCredentialsStore(FlutterSecureStorage());
});

final hevyApiClientProvider = Provider<HevyApiClient>((ref) {
  final client = HevyApiClient(
    httpClient: http.Client(),
    credentials: ref.watch(hevyCredentialsStoreProvider),
  );
  ref.onDispose(client.close);
  return client;
});
```

## Next PR

1. Add normalized Drift tables for workouts, exercises, and sets.
2. Implement `HevyWorkoutSink` with transactional upserts.
3. Add a migration and generated Drift code.
4. Add a Health Integrations screen with connect, verify, sync, and disconnect.
5. Store sync metadata locally and implement `/v1/workouts/events`.
6. Add read-only dashboard metrics only after imported data is validated.
