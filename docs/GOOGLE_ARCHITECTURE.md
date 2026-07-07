# Google Architecture — NeuroFlow

**Status:** Shipped (Google Foundation Sprint, Stages 4–7) · **Branch:** `claude/neuroflow-phase-2-sprint-f93s85`
**Scope:** the Google account/auth foundation and the generic sync framework. **No product
API client (Tasks, Calendar, Gmail, Drive, Contacts, Gemini) exists yet** — this document
describes plumbing, not features.
**Design source:** `STAGE2_COMPONENT_DESIGN.md` (revision 2, post adversarial-critic
review). **Authoritative source for deviations:** `DECISIONS.md` → search "Google
Foundation Sprint" (three entries: Stages 4–5, Stage 6, and a QA fix). Where this document
and the design doc disagree, this document follows the shipped code, and the disagreement
is called out inline.
**Related docs:** `docs/GOOGLE_SETUP.md` (Google Cloud / OAuth client setup checklist — not
duplicated here), `docs/GOOGLE_INTEGRATION.md` (how to extend this), `docs/CONNECTED_SERVICES.md`
(the Settings feature this powers).

---

## 1. Architecture diagram

```
┌───────────────────────────────────────────────────────────────────────────────┐
│ PRESENTATION  (lib/presentation/)                                             │
│   settings_screen.dart — "Connected Services" section:                       │
│     _GoogleAccountTile / _GoogleAccountCard   (the ONE functional action:     │
│       connect() / disconnect(), watches googleConnectionStateProvider)       │
│     _MoreServicesList / _ComingSoonServiceTile (every row inert this sprint,  │
│       watches connectedServicesProvider, taps call enableService())          │
│   Imports ONLY providers.dart + pure domain types (google_connection_state,   │
│   google_service) — never google_sign_in, never lib/platform/google/*.        │
└───────────────┬────────────────────────────────────────────────────────────────┘
                │ ref.watch(googleConnectionStateProvider)
                │ ref.watch(connectedServicesProvider)
                │ ref.read(googleServiceManagerProvider).{connect,disconnect,enableService}()
┌───────────────▼────────────────────────────────────────────────────────────────┐
│ EXECUTIVE  (lib/executive/)                        UNCHANGED — Google-agnostic │
│   Planner / LexiPlanAdvisor never reference Google in any form. The Google     │
│   stack is side-by-side infrastructure Presentation talks to directly through  │
│   providers — Executive does not sit between them.                            │
└───────────────┬────────────────────────────────────────────────────────────────┘
                │
┌───────────────▼────────────────────────────────────────────────────────────────┐
│ PLATFORM  (lib/platform/)                                                       │
│                                                                                  │
│  lib/platform/google/   (the ONLY directory that imports package:google_sign_in)│
│  ┌────────────────────────────────────────────────────────────────────────────┐│
│  │            GoogleServiceManager  (facade — google_service_manager.dart)    ││
│  │  5 injected deps: auth, accounts, permissions, apiFactory, services.        ││
│  │  (Design doc §2.1 specified 6, incl. SyncEngine — dropped; see §6 below.)   ││
│  │      │              │                   │                   │              ││
│  │      ▼              ▼                   ▼                   ▼              ││
│  │ GoogleSignIn   GooglePermission     GoogleApiFactory   ConnectedServices   ││
│  │ AuthRepository Manager(Impl)        Impl                Repository (Data) ││
│  │  wraps          scope request +      authed http.Client   layer, injected ││
│  │  google_sign_in cache; no Drift      cache; per-service;  — see DATA below││
│  │      │          writes               401 → onAuthFailure                  ││
│  │      │ ID token → FlutterSecureStorage    callback                        ││
│  │      │ (access token: NEVER persisted;                                     ││
│  │      │  read live from the plugin every call)                             ││
│  │      │                                    registerServiceIntegration() /   ││
│  │      │                                    clientFor(GoogleServiceId) —     ││
│  │      │                                    registry is real, unpopulated    ││
│  └──────┼──────────────────────────────────────────────────────────────────────┘│
│         │                                                                       │
│  lib/platform/sync/  (EXISTING queue infra + one NEW, independent component)    │
│  ┌──────────────────────────────────────────────────────────────────────────┐  │
│  │ SyncEngine / DefaultSyncEngine (generic; ZERO Google imports; 0 channels  │  │
│  │   registered — has its own provider, is NOT a GoogleServiceManager dep)   │  │
│  │ GoogleTasksSyncService (EXISTING, byte-identical, still dormant — reads   │  │
│  │   the legacy `neuroflow_google_tasks_token` key, a separate token store)  │  │
│  │ ForegroundSyncObserver / BackgroundScheduler (EXISTING, unchanged)        │  │
│  └──────────────────────────────────────────────────────────────────────────┘  │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────────────────────┐
│ DATA  (lib/data/)                                                              │
│   Interfaces: GoogleAuthRepository · GoogleAccountRepository ·                 │
│               ConnectedServicesRepository                                      │
│   Drift impls: DriftGoogleAccountRepository, DriftConnectedServicesRepository  │
│   AppDatabase: v4→v5 adds GoogleAccounts, v5→v6 adds ConnectedServices          │
│   (two separate, sequential migrations — see §6, not the design's single       │
│   combined v4→v5 step)                                                         │
└───────────────┬────────────────────────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────────────────────┐
│ DOMAIN  (lib/domain/) — pure Dart, no Flutter/Drift/plugin imports              │
│   GoogleConnectionState + GoogleConnectionStatus (isLegalTransition())         │
│   GoogleAccount (metadata only; estimateExpiry())                             │
│   GoogleServiceId, GoogleServiceStatus, ConnectedService                      │
└────────────────────────────────────────────────────────────────────────────────┘
```

Layer rule (unchanged from the design doc, verified against the shipped tree):
`lib/domain/` imports nothing platform-specific; `lib/data/` holds abstract interfaces plus
Drift impls; `lib/platform/google/` is the only directory that imports
`package:google_sign_in`; `lib/providers.dart` is the sole composition root. `settings_screen.dart`
imports only `providers.dart` and the two pure-domain files — confirmed by inspection of its
import block.

---

## 2. Component specifications

### 2.1 GoogleServiceManager

**File:** `lib/platform/google/google_service_manager.dart`
**Responsibility:** the single facade every Google interaction in the app passes through —
owns the `GoogleConnectionState` state machine, coordinates auth, permissions, API-client
creation, the service registry, and Connected Services status.

**Constructor deps (shipped, 5):** `GoogleAuthRepository auth`, `GoogleAccountRepository
accounts`, `GooglePermissionManager permissions`, `GoogleApiFactory apiFactory`,
`ConnectedServicesRepository services`. **No `SyncEngine` dependency** — see §6.

**Key methods:**
- `watchConnectionState()` — broadcast stream, replays the current state to new listeners
  (a `StreamController.broadcast()` does not replay by default, so this is wrapped in an
  `async*` generator that yields `_current` before `_controller.stream`).
- `currentState` — synchronous, starts as `GoogleConnectionState.disconnected()`.
- `initialize()` — app-start silent restore. Distinguishes "never connected"
  (→ stays `disconnected`) from "a previous session existed but silent restore failed"
  (→ `expired`, recoverable via `connect()`) from an unexpected plugin/network exception
  (→ `error`).
- `connect()` / `disconnect({bool forget = false})` — interactive sign-in / sign-out.
  `disconnect()` is a soft disconnect by default (keeps the account metadata row so
  reconnect is one tap); `forget: true` also removes the row.
- `refreshSession()` — forces a token refresh; no-op when disconnected.
- `notifyAuthFailure()` — package-visible callback invoked by `GoogleApiFactory` on a live
  401; the only path that reaches `GoogleConnectionStatus.expired` from real traffic.
- `registerServiceIntegration(GoogleServiceIntegration)` / `clientFor(GoogleServiceId)` —
  the extension seam (see §7). Real and implemented; the registry is empty this sprint.
- `enableService(GoogleServiceId)` — see §2.6; always returns `false` this sprint.
- `dispose()`.

**Explicitly does NOT:** perform OAuth itself (delegates to `GoogleAuthRepository`);
persist anything directly (delegates to the two repositories); construct product API
clients; run sync operations; render UI; log tokens, IDs, or account identifiers (only
sanitized state-transition-shaped messages).

### 2.2 GoogleAuthRepository / GoogleSignInAuthRepository

**Interface:** `lib/data/google_auth_repository.dart`
**Impl:** `lib/platform/google/google_auth_repository_impl.dart`

Auth operations only: `signIn()`, `silentSignIn()`, `signOut()`, `refreshToken()`,
`currentAccessToken()`. Returns `GoogleAccount` metadata — never a token.

- **Cancellation:** on Android the plugin returns `null` from `signIn()`; on iOS (and some
  Android paths) it throws `PlatformException(code: 'sign_in_canceled'/'sign_in_cancelled')`.
  The impl catches both codes and maps them to `null` so cancel is never
  `GoogleConnectionStatus.error`. Other `PlatformException`s are rethrown as
  `GoogleAuthException`.
- **Token handling:** the ID token is written to `FlutterSecureStorage` under
  `neuroflow_google_id_token_<accountId>` and deleted on `signOut()` (the account id is
  captured *before* calling `_plugin.signOut()`, since `currentUser` is `null`
  immediately afterward). **The access token is never persisted anywhere.**
  `currentAccessToken()` reads `GoogleSignIn.currentUser.authentication` fresh on every
  call — never a stored copy — because a stored copy would be stale within about an hour
  and the existing background sync cadence is 4 hours.
- `refreshToken()` throws `GoogleAuthTokenExpiredException` (a `GoogleAuthException`
  subtype) when silent restore fails; `GoogleServiceManager` maps that to
  `GoogleConnectionStatus.expired`.

**Explicitly does NOT:** persist metadata to Drift (`GoogleAccountRepository`'s job);
request scopes beyond the base `email`/`profile` (`GooglePermissionManager`'s job); track
multiple accounts; own connection state.

### 2.3 GoogleAccountRepository / DriftGoogleAccountRepository

**Interface:** `lib/data/google_account_repository.dart`
**Impl:** `lib/data/google_account_repository_impl.dart`

Drift-backed persistence of account **metadata** — `watchAccounts()`, `getPrimary()`,
`upsert()`, `setPrimary(accountId)`, `touch(accountId, {lastRefreshAt,
tokenExpiresAtEstimate, grantedScopes})`, `remove()`, `clearAll()`.

- `setPrimary` and `upsert` run inside `AppDatabase.transaction()` (demote-all +
  promote-one is atomic).
- `getPrimary()` self-heals: if it observes zero or more than one `isPrimary` row (crash
  mid-write, cloned DB), it deterministically repairs to the most-recently-`connectedAt`
  row inside the same transaction rather than erroring.
- `touch()` is the **single writer** of `grantedScopes` at rest — called only by
  `GoogleServiceManager`, never by `GooglePermissionManager` or UI.
- Multi-account shape (`watchAccounts()` returns a list, `setPrimary`) is kept for
  future-proofing, but no `switchAccount` exists and nothing but the first-connected
  account is ever made primary this sprint (see §6).

**Explicitly does NOT:** call `google_sign_in` or any network API; read/write
`FlutterSecureStorage`; decide who is signed in; store a token (the schema physically has
no token column).

### 2.4 GooglePermissionManager / GooglePermissionManagerImpl

**Interface:** `lib/platform/google/google_permission_manager.dart`
**Impl:** `lib/platform/google/google_permission_manager_impl.dart`

OAuth scope request + in-memory cache, nothing else: `hydrate(grantedScopes)`,
`hasScopes(scopes)`, `ensureScopes(scopes) → ScopeGrantResult`, `grantedScopes` getter,
`clear()`.

- **No `GoogleAccountRepository` dependency** — `GoogleServiceManager` is the single
  writer of `grantedScopes` at rest; this class only ever holds an in-memory `Set<String>`
  seeded via `hydrate()`.
- `google_sign_in` v6.2.1 exposes no "list granted scopes" getter, so the cache is
  necessarily "scopes we requested and the plugin returned `true` for" — externally
  revoked scopes are only observable via a future API 403 (a documented open gap).
- `ensureScopes()` on a signed-out plugin short-circuits to `ScopeGrantOutcome.notSignedIn`
  without ever prompting the sign-in UI.

**Explicitly does NOT:** sign in/out; store tokens; write to Drift; know which scope
belongs to which product service (callers pass scopes; the mapping lives in
`GoogleServiceIntegration.requiredScopes`).

### 2.5 GoogleApiFactory / GoogleApiFactoryImpl

**Interface:** `lib/platform/google/google_api_factory.dart`
**Impl:** `lib/platform/google/google_api_factory_impl.dart`

Creates and caches authenticated `http.Client` objects — the only place an access token
becomes an `Authorization` header. `clientFor(GoogleServiceId, {required requiredScopes})`
returns `null` when signed out or the required scopes aren't granted (never throws for
"not signed in"); `invalidate()` closes and drops every cached client;
`wireAuthFailureCallback(void Function())` is a **post-construction setter** (not a
constructor argument) — a constructor-time callback into `GoogleServiceManager` would be
circular in the Riverpod provider graph, since the manager depends on this factory. The
factory stores it behind a trampoline closure so clients created before or after the wiring
call still pick up the current callback.

- `_AuthenticatedClient extends http.BaseClient` reads
  `GoogleAuthRepository.currentAccessToken()` at `send()` time (so a refresh propagates
  without cache invalidation) and, on a live 401, invokes the wired callback exactly once —
  this is what actually drives `connected → expired` in practice (see §2.7).
- Clients are cached per `GoogleServiceId` only, not per `(accountId, service)` — single
  active account, no `switchAccount`, so this is safe this sprint (see §6).
- The client does not retry itself.

**Explicitly does NOT:** construct `TasksApi`/`CalendarApi`/any `googleapis` product
class; perform sign-in or scope prompts (returns `null` instead); cache tokens (only
clients); get called from widgets (manager-only consumer).

### 2.6 ConnectedServicesRepository / DriftConnectedServicesRepository

**Interface:** `lib/data/connected_services_repository.dart`
**Impl:** `lib/data/connected_services_repository_impl.dart`

Drift-backed, account-independent status for the 7 `GoogleServiceId` rows:
`watchAll()`, `get(id)`, `setStatus(id, status)`, `touchLastUsed(id)`, `clearAll()`.

- **Seeding fix:** the design doc originally specified lazy seeding inside `watchAll()`'s
  stream pipeline — flagged (`STAGE2_CRITIC_REPORT.md` m5) as a write-triggers-rewatch
  risk. Shipped fix: a `Future<void> _seeded` is kicked off once in the constructor
  (idempotent insert-one-comingSoon-row-per-missing-`GoogleServiceId`); every public
  method `await`s it before touching the table; `clearAll()` re-seeds immediately after
  wiping the table.
- `GoogleServiceManager.enableService(id)` calls `touchLastUsed(id)` — **not**
  `setStatus()` — and always returns `false`. `status` is reserved for a real state
  transition (`comingSoon → available/enabled/disabled`) that only a future sprint with an
  actual product client may perform; `lastUsedAt` is a cheap, honest "user tapped this row"
  signal (see `DECISIONS.md`, Stage 6 entry, and `docs/CONNECTED_SERVICES.md`).

**Explicitly does NOT:** enable anything for real (no scope requests, no clients); know
about accounts or tokens; gate any app feature.

### 2.7 GoogleConnectionState

**File:** `lib/domain/google_connection_state.dart` — pure Dart, no imports beyond `dart:core`.

`GoogleConnectionStatus` has 5 values: `disconnected`, `connecting`, `connected`, `expired`,
`error`. `GoogleConnectionState` carries `status`, `email`, `displayName`, `grantedScopes`,
`lastError` (sanitized, user-displayable, never a token/ID/stack trace), `lastRefreshAt`,
`connectedAt` — metadata only, never a token.

**Transition table, read directly from `GoogleConnectionState.isLegalTransition()`
(current shipped code, not the pre-fix design-doc version):**

```
                     initialize(): no prior session   ──(stay)──┐
                     connect(): user cancelled        ──(stay)──┤
            ┌───────────────────────────────────────────────────▼──┐
            │                     disconnected                      │◄──────────────┐
            └───────────────┬────────────────────────────────────────┘              │
                            │ connect() / initialize() with a prior session          │
                            ▼                                                       │
            ┌───────────────────────────┐    unexpected plugin/network failure      │
            │        connecting        ├──────────────────────────────┐             │
            └───┬───────────────┬───────┘                             ▼             │
                │ success        │ initialize(): prior session exists  ┌───────────┐│
                ▼                │ but silent restore fails             │   error   ││
            ┌───────────┐        ▼                                     └─────┬─────┘│
            │ connected │◄──────────────────────────┐                        │      │
            └──┬─────┬──┘   refreshSession() ok       │  disconnect()        │      │
               │     │      (via connecting)          │                      │      │
               │     │ notifyAuthFailure() (401)       │                     │      │
               │     ▼                                 │                    │      │
               │  ┌─────────┐  connect()/refreshSession() (via connecting) ──┘      │
               │  │ expired ├───────────────────────────────────────────────────────┤
               │  └────┬────┘                                                       │
               │       │ silent refresh fails → error; or disconnect()              │
               │ disconnect()                                                       │
               └─────────────────────────────────────────────────────────────────►  ▼
                                                                              disconnected
```

Legal transitions (exact, from `isLegalTransition()`):

| From | Legal `to` |
|---|---|
| `disconnected` | `{connecting}` |
| `connecting` | `{connected, expired, error, disconnected}` |
| `connected` | `{expired, connecting, disconnected}` |
| `expired` | `{connecting, error, disconnected}` |
| `error` | `{connecting, disconnected}` |

A same-status update (e.g. a `touch()`-driven metadata refresh) is always legal — it isn't
a state-machine move. `connecting → expired` is the one addition the design doc's
revision 2 made over its first draft (fix for M5): it covers `initialize()` finding a
persisted account row that silent restore couldn't resurrect, distinct from
`connecting → error` (an unexpected plugin/network exception). `GoogleServiceManager`
asserts every transition against this table in debug builds.

**Explicitly does NOT:** hold tokens; know how transitions happen (no side-effecting
methods); import Flutter, Drift, or any plugin.

### 2.8 SyncEngine / DefaultSyncEngine

**Interface:** `lib/platform/sync/sync_engine.dart`
**Impl:** `lib/platform/sync/sync_engine_impl.dart`

Generic offline-first sync framework with **zero Google imports** — `SyncChannel` pairs a
`SyncQueueRepository` (the existing, unmodified interface) with a `SyncExecutor`. This
sprint **no channel is ever registered** (`syncEngineProvider` constructs a bare
`DefaultSyncEngine`; nothing calls `registerChannel()`), so `flush()` always takes the
`SyncReport.idle` fast path, `progress` and `reports` streams emit their idle values.

- `BackoffPolicy.delayFor(retryCount)` is real and used, but **within a single `flush()`
  call only** — `SyncQueue` has no `nextAttemptAt`/due-time column, so durable,
  cross-flush-delayed retries are not implementable on the current schema and are not
  shipped (see `docs/GOOGLE_INTEGRATION.md` §"Known deferred items", M7).
- `ConflictResolver.resolve(local, remoteSnapshot)` takes the remote snapshot as a second
  parameter (fix for m8 — the design doc's first draft only passed the local op, which
  could never actually express `keepRemote`); `LastWriteWinsResolver` ignores it and
  always returns `keepLocal`.
- Failure taxonomy (`SyncFailureKind`): `transientNetwork` → `incrementRetry`;
  `authRequired` → stop flushing the channel for the rest of this call, leave ops
  pending, do **not** `incrementRetry` (it's "paused", not "failed"); `conflict` →
  `ConflictResolver`; `permanent` → `markDone`-with-failure (no retry).
- `GoogleTasksSyncService` (existing) is untouched and remains the sole flusher of the
  legacy tasks queue; a future sprint would replace its `flush()` body with
  `engine.flush(channelId: 'google.tasks')` after registering a channel — see the
  background-isolate deferral in `docs/GOOGLE_INTEGRATION.md`.
- `SyncEngine` is **not** a `GoogleServiceManager` dependency — it has its own,
  independent `syncEngineProvider` (see §6). There is no `syncProgressProvider` in
  `providers.dart` yet; that pointer comment is left in `providers.dart` for a follow-up.

**Explicitly does NOT:** import anything Google-specific; create HTTP clients; know about
tasks/calendars/any domain type beyond `SyncOperation`; run on a timer; replace
`GoogleTasksSyncService` this sprint; log operation payloads.

---

## 3. Drift schema additions

**File:** `lib/data/database.dart`. Two additive migrations — `schemaVersion` is now `6`
(was `4` before this sprint): `if (from < 5) { createTable(googleAccounts); }` then
`if (from < 6) { createTable(connectedServices); }`, each its own block. See §6 for why
this is two migrations, not the design doc's single combined v4→v5 step.

### `GoogleAccounts` (added v5) — `@DataClassName('GoogleAccountRow')`

| Column | Type | Notes |
|---|---|---|
| `id` | `TextColumn` (PK) | stable id from `google_sign_in` |
| `email` | `TextColumn` | |
| `displayName` | `TextColumn?` | nullable |
| `photoUrl` | `TextColumn?` | nullable |
| `grantedScopes` | `TextColumn` | space-separated; default `''` |
| `isPrimary` | `BoolColumn` | default `false` |
| `connectedAt` | `DateTimeColumn` | |
| `lastRefreshAt` | `DateTimeColumn?` | nullable |
| `tokenExpiresAtEstimate` | `DateTimeColumn?` | nullable; **derived**, advisory-only — never authoritative, never a token |

No column holds a token, and none ever will — adding one is a review-blocking regression
per the file's own header comment.

### `ConnectedServices` (added v6) — `@DataClassName('ConnectedServiceRow')`

| Column | Type | Notes |
|---|---|---|
| `serviceId` | `TextColumn` (PK) | `GoogleServiceId.name` |
| `status` | `TextColumn` | `'comingSoon' \| 'available' \| 'enabled' \| 'disabled'`, default `'comingSoon'` |
| `enabledAt` | `DateTimeColumn?` | nullable |
| `lastUsedAt` | `DateTimeColumn?` | nullable |

Pure additive migrations — no data transforms, no changes to any pre-existing table
(`Tasks`, `SyncQueue`, `Habits`, `HabitCheckIns`, `Routines`, `RoutineSteps`).
`AppDatabase` also exposes low-level query primitives for both tables (`watchGoogleAccounts`,
`fetchGoogleAccounts`, `upsertGoogleAccount`, `demoteAllGoogleAccounts`,
`promoteGoogleAccount`, `touchGoogleAccount`, `removeGoogleAccount`, `clearGoogleAccounts`,
and the mirrored `*ConnectedServices` set), consumed only by the two Drift repository
implementations above.

---

## 4. Riverpod providers (`lib/providers.dart`)

The full, current list — more than the original design doc's table, layered in across
Stages 4–7:

| Provider | Type | Creates / notes |
|---|---|---|
| `googleSignInPluginProvider` | `Provider<GoogleSignIn>` | shared plugin instance, base scopes `[email, profile]` only. Never watched by widgets. |
| `googleAuthRepositoryProvider` | `Provider<GoogleAuthRepository>` | `GoogleSignInAuthRepository(plugin)` |
| `googleAccountRepositoryProvider` | `Provider<GoogleAccountRepository>` | `DriftGoogleAccountRepository(db)` |
| `googlePermissionManagerProvider` | `Provider<GooglePermissionManager>` | `GooglePermissionManagerImpl(plugin)` — no account-repo dep |
| `googleApiFactoryProvider` | `Provider<GoogleApiFactory>` | `GoogleApiFactoryImpl(authRepo, permissionManager)`; `ref.onDispose(factory.invalidate)` |
| `connectedServicesRepositoryProvider` | `Provider<ConnectedServicesRepository>` | `DriftConnectedServicesRepository(db)` |
| `googleServiceManagerProvider` | `Provider<GoogleServiceManager>` | facade wired with 5 deps; wires `apiFactory.wireAuthFailureCallback(manager.notifyAuthFailure)` post-construction; `ref.onDispose(manager.dispose)` |
| `googleConnectionStateProvider` | `StreamProvider<GoogleConnectionState>` | `manager.watchConnectionState()` — the only Google surface widgets watch for reads |
| `connectedServicesProvider` | `StreamProvider<List<ConnectedService>>` | `connectedServicesRepository.watchAll()` — read directly by Settings; writes still go through the manager |
| `syncEngineProvider` | `Provider<SyncEngine>` | `DefaultSyncEngine(connectivityProbe: SocketConnectivityProbe())`; `ref.onDispose(engine.dispose)`; **independent of the Google provider tree** |
| `googleTasksSyncServiceProvider` | `Provider<GoogleTasksSyncService>` | existing, unchanged, dormant until the legacy token key is written |

Not shipped: `syncProgressProvider` (design doc listed it; a one-line scope-note pointer in
`providers.dart` defers it — nothing currently surfaces `SyncEngine.progress` to the UI).

**Dependency graph:**

```
googleConnectionStateProvider ──► googleServiceManagerProvider
connectedServicesProvider ──────► connectedServicesRepositoryProvider ─► databaseProvider

googleServiceManagerProvider ──► googleAuthRepositoryProvider ───────► googleSignInPluginProvider
                              ├► googleAccountRepositoryProvider ────► databaseProvider
                              ├► googlePermissionManagerProvider ───► googleSignInPluginProvider
                              ├► googleApiFactoryProvider ──────────► googleAuthRepositoryProvider
                              │                                    └► googlePermissionManagerProvider
                              └► connectedServicesRepositoryProvider

syncEngineProvider  (standalone — no edges to/from the Google graph above)

(existing, unchanged) googleTasksSyncServiceProvider ─► syncQueueRepositoryProvider ─► databaseProvider
```

Acyclic. `GoogleServiceManager` is the top of the Google graph and the only node
Presentation touches for actions (`ref.read(googleServiceManagerProvider)`);
`googleConnectionStateProvider` and `connectedServicesProvider` are the only two nodes
Presentation watches for reads. App startup calls
`container.read(googleServiceManagerProvider).initialize()` fire-and-forget, try/catch-wrapped,
from `lib/main.dart` (alongside where `ForegroundSyncObserver` is started).

---

## 5. Extension points

Two independent registration seams exist for a future sprint to plug a real product
integration (e.g. Google Tasks) into. Neither is populated today; both are illustrative
shapes, not real code — no product client of any kind exists yet.

### 5.1 `GoogleServiceManager.registerServiceIntegration` — the auth/scopes/client seam

```dart
// Illustrative shape only — no GoogleTasksIntegration ships this sprint.
manager.registerServiceIntegration(GoogleServiceIntegration(
  id: GoogleServiceId.tasks,
  requiredScopes: [GoogleScopes.tasks],
  onClientReady: (http.Client client) {
    // A future sprint builds its own googleapis-backed wrapper here,
    // behind this callback — never in a widget, never inside the manager.
  },
));

// Later, once enableService()/some future flow grants the scopes:
final client = await manager.clientFor(GoogleServiceId.tasks);
// null if disconnected, unregistered, or scopes not granted.
```

### 5.2 `SyncEngine.registerChannel` — the durable-queue seam

```dart
// Illustrative shape only — no SyncExecutor implementation ships this sprint.
syncEngine.registerChannel(SyncChannel(
  id: 'google.tasks',
  queue: driftSyncQueueRepository,       // the EXISTING, unmodified interface
  executor: someFutureTasksSyncExecutor, // implements SyncExecutor.execute(op)
  // conflictResolver / backoff default to LastWriteWinsResolver / BackoffPolicy()
));

final report = await syncEngine.flush(channelId: 'google.tasks');
```

Both seams are real, tested-by-construction machinery — they simply have nothing
registered. See `docs/GOOGLE_INTEGRATION.md` for the practical "how do I add a new Google
product" walkthrough, including the seams' constraints and the open problems (background
isolate token acquisition, non-durable backoff) a future sprint needs to resolve before
either seam sees its first real registrant.

---

## 6. Deviations from `STAGE2_COMPONENT_DESIGN.md` (see `DECISIONS.md` for full detail)

- `GoogleServiceManager` ships with **5** constructor deps, not the design's 6 —
  `SyncEngine` was dropped; nothing in the facade's current surface needs it, and wiring
  it in a circular-dependency-free way is left to whichever future sprint registers the
  first channel through it.
- The combined v4→v5 `GoogleAccounts` + `ConnectedServices` migration in the design doc
  shipped as **two** sequential migrations, v4→v5 (Stage 4, `GoogleAccounts` only) then
  v5→v6 (Stage 6, `ConnectedServices` only) — two parallel implementation stages could not
  both safely bump the same `schemaVersion`/`onUpgrade` block at once.
- `GoogleApiFactory`'s 401 callback is wired via a post-construction setter
  (`wireAuthFailureCallback`), not a constructor argument — a constructor-time wiring would
  be circular in the Riverpod graph (the manager depends on the factory).
- `_reconcile()`'s `grantedScopes` merge is a **union** of fresh and existing scopes, not
  "fresh wins" — a QA fix after the base auth scopes were found to always be non-empty,
  which made the original "fresh wins" logic's fallback branch permanently dead code and
  would have silently downgraded any future incrementally-granted scope back to
  `email`/`profile` on every silent restore.
- No `syncProgressProvider` ships — `SyncEngine.progress` is not yet surfaced to any widget.

All of the design doc's revision-2 fixes (M1–M7, m1, m3, m4) are reflected as shipped
behavior in the component sections above; none required further rearchitecting during
implementation.
