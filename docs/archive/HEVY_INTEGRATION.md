# Hevy integration — read-only persistence

## Scope

This first slice intentionally supports read-only access:

- Securely save and clear the user's Hevy API key.
- Verify the key with `GET /v1/user/info`.
- Read workout count.
- Read paginated workouts.
- Read a single workout.
- Import all workouts through a persistence boundary.
- Cache normalized workouts, exercises, and sets in Drift.
- Reconcile each workout transactionally and without duplicate records.
- Retain cached workouts and local sync status when a later sync fails.
- Connect, manually sync, and disconnect from the Health Integrations screen.
- Review recent imported workouts while connected or disconnected.

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

`lib/app/providers.dart` exports a narrowly grouped Hevy provider module. It
owns secure credentials, the disposable HTTP client, API client, Drift
repository, sync service, connection controller, sync state, imported count,
and recent-workout stream. Presentation code reads these providers and never
constructs infrastructure directly. Provider state never contains the API key,
and no Hevy provider is connected to Lexi or Intelligence.

## Health Integrations screen

Settings links to `/settings/health-integrations`. The Hevy card supports not
connected, verifying, connected, syncing, sync complete, and safe error states.
Rejected credentials are removed. Disconnect removes only the credential;
imported history remains available. The recent-workout proof view shows local
date, duration, exercise count, and set count without analysis or fitness
evaluation.

## Persistence

The database stores Hevy workouts, exercises, and sets in normalized tables.
The stable Hevy workout ID is the upsert key; child IDs combine their parent ID
and Hevy position. Re-importing a changed workout replaces its children inside
the same transaction, so stale child records are removed and partial workouts
cannot be committed. Sync attempts, successes, failure type, and import count
are stored separately. API keys and response bodies are never persisted.

## Future work

1. Implement incremental `/v1/workouts/events` sync and its deletion policy.
2. Add read-only dashboard metrics only after imported data is validated.
