# Google Integration Guide — how to extend this

**Audience:** engineers building the first real Google product integration (Tasks,
Calendar, Gmail, Drive, Contacts, Gemini) on top of the Google Foundation Sprint.
**Read first:** `docs/GOOGLE_ARCHITECTURE.md` for the architecture diagram, component
specs, provider list, and extension-point sketches — this document does not repeat them.
**Authoritative for "why" questions:** `DECISIONS.md` (search "Google Foundation Sprint")
and `STAGE2_CRITIC_REPORT.md`.

Nothing in this document implies a product client exists today. `googleapis` is an unused
dependency; every code sketch below is illustrative shape, not real code.

---

## 1. How to add a new Google product integration, end to end

Worked example: Google Tasks (the first, most likely candidate — `GoogleTasksSyncService`
already has dormant plumbing waiting for it).

### 1.1 What you'd create

- A `TasksSyncExecutor implements SyncExecutor` (new file, e.g.
  `lib/platform/google/tasks_sync_executor.dart` or alongside `GoogleTasksSyncService`) —
  the only place that constructs a `googleapis` `TasksApi` and translates `SyncOperation`s
  into real Tasks API calls.
- A `GoogleServiceIntegration` descriptor for `GoogleServiceId.tasks`, registered once at
  app startup (alongside where `googleServiceManagerProvider` is read in `main.dart`).
- A `SyncChannel` (`id: 'google.tasks'`, wrapping the *existing*
  `DriftSyncQueueRepository` and your new `TasksSyncExecutor`), registered on
  `syncEngineProvider` once at startup.
- Whatever UI change flips `enableService()`'s behavior for `tasks` from the current
  hardcoded no-op to a real scope-request + `setStatus(enabled)` flow (see §3 of
  `docs/CONNECTED_SERVICES.md`).

### 1.2 Which existing seams you plug into

- **`GoogleServiceManager.registerServiceIntegration(GoogleServiceIntegration)`** — supply
  `id: GoogleServiceId.tasks`, `requiredScopes: [GoogleScopes.tasks]`, and an
  `onClientReady(http.Client)` callback that builds your `TasksApi` wrapper. Call
  `manager.clientFor(GoogleServiceId.tasks)` to get an authenticated `http.Client` once
  scopes are granted — `GoogleApiFactory` handles token injection and cache invalidation
  for you.
- **`GoogleApiFactory.clientFor`** (indirect, via the manager) — never construct your own
  `http.Client` with a token; this is the only place a token becomes an `Authorization`
  header in the entire app.
- **`SyncEngine.registerChannel(SyncChannel)`** — reuse `DriftSyncQueueRepository`
  verbatim; do not create a second queue implementation. Your `SyncExecutor.execute(op)`
  is the only new code that talks to the Tasks API.
- **`GooglePermissionManager.ensureScopes([GoogleScopes.tasks])`** — call this (via the
  manager, or however future sprint wiring exposes it) before assuming
  `hasScopes`/`clientFor` will succeed; it drives the incremental-auth prompt.

### 1.3 What you must NOT do

- **Do not bypass `GoogleServiceManager`.** It is the single facade; nothing else in the
  app should call `GoogleAuthRepository`, `GooglePermissionManager`, or `GoogleApiFactory`
  directly — including your new integration code, which should be constructed and
  registered from the composition root (`providers.dart`/`main.dart`), not reach around
  the manager at call time.
- **Do not add a second `GoogleSignIn` instance.** `googleSignInPluginProvider` is the one
  shared plugin instance (`lib/providers.dart`); a second instance would desync sign-in
  state and scope grants from everything already wired to the first.
- **Do not store a token anywhere but `FlutterSecureStorage` — and never an access token
  at all.** The ID token is the only token this codebase persists
  (`neuroflow_google_id_token_<accountId>`, written/deleted exclusively by
  `GoogleSignInAuthRepository`). Access tokens are read live from the plugin
  (`currentAccessToken()`) every time they're needed; adding a stored-access-token key is
  a review-blocking regression (see `lib/data/database.dart`'s own header comment on
  `GoogleAccounts`, and `docs/GOOGLE_ARCHITECTURE.md` §2.2).
- **Do not construct a product API class (`TasksApi`, `CalendarApi`, …) inside
  `GoogleApiFactory` or `GoogleServiceManager`.** Those two classes only ever hand out a
  raw authenticated `http.Client`; product-client construction happens in your
  integration's own code, behind `GoogleServiceIntegration.onClientReady`.
- **Do not write `ConnectedServicesRepository.status` from anywhere but
  `GoogleServiceManager`.** Widgets go through `enableService()`; there is no other
  sanctioned writer.
- **Do not generalize `SyncOperation`'s payload or add a `nextAttemptAt` column to
  `SyncQueue` as a side effect of "just wiring in Tasks."** Both are known, deliberately
  deferred refactors (see §2, M7) — pull them into their own reviewed change if your
  integration actually needs them, don't fold them into a feature PR.

---

## 2. Known deferred / open items

These are load-bearing gaps a future engineer needs to know about before building on top
of this foundation — pulled from `DECISIONS.md`'s own framing, not re-litigated here.

- **M6 — background-isolate token acquisition is an open problem.** `BackgroundScheduler`'s
  `_runSyncFlush` runs in a fresh WorkManager isolate with no `ProviderContainer`; it
  hand-constructs `AppDatabase()` → `DriftSyncQueueRepository` → `GoogleTasksSyncService`
  from scratch every time. A `SyncEngine`-backed Tasks channel needs the same isolate to
  also construct a `GoogleApiFactory` → `GoogleAuthRepository` → `GoogleSignIn` plugin
  chain to get a token — and silent sign-in from a headless isolate is unproven, while a
  stored access token (per the no-persistence rule above) doesn't exist to fall back on.
  This sprint's `SyncEngine` has zero registered channels, so the problem is dormant, not
  solved. Two candidate options to evaluate when this is tackled: (a) attempt
  `signInSilently()` inside the isolate after `DartPluginRegistrant.ensureInitialized()`,
  or (b) make Google-backed channels foreground-only (skip them in background flushes;
  rely on `ForegroundSyncObserver` instead).
- **M7 — no durable cross-flush retry scheduling.** `BackoffPolicy.delayFor(retryCount)` is
  implemented and used, but only to space out retries *within a single* `flush()` call.
  `SyncQueue` has no `nextAttemptAt`/due-time column, and `SyncQueueRepository.fetchPending()`
  can't filter by due-time, so a failed op is retried on the very next flush regardless of
  what `delayFor` computed. Durable backoff requires adding a due-time column — deferred to
  the same future sprint that generalizes `SyncOperation`'s payload, not something to sneak
  into a channel-registration PR.
- **M1 — no `switchAccount`, single-account-only this sprint.** `google_sign_in` ^6.2.1 has
  no account-targeted silent sign-in (only one `currentUser` at a time).
  `GoogleAccountRepository` keeps its N-account shape (`watchAccounts()` returns a list,
  `setPrimary` exists) because it costs nothing, but nothing consumes it beyond "first
  connected account becomes primary." A future multi-account sprint would respecify
  `switchAccount` as an interactive `signIn()` whose returned account is compared against
  the requested id — not a silent targeted restore, because the plugin cannot do that.
- **`grantedScopes` union-not-overwrite fix, and why scope revocation detection is still an
  open gap.** `GoogleServiceManager._reconcile()` computes `grantedScopes` as the union of
  the auth layer's freshly-reported base scopes (`email`, `profile` — that's all
  `GoogleSignInAuthRepository._toAccount()` ever reports) and whatever was previously
  persisted, rather than trusting the fresh value alone. This matters the moment your
  integration persists an incrementally-granted scope (e.g. `GoogleScopes.tasks`) via
  `GoogleAccountRepository.touch(grantedScopes: ...)` — without the union, every subsequent
  `initialize()`/`refreshSession()` would silently downgrade the account back to just
  `email`/`profile`. What the union fix does **not** do: detect a scope the user revoked
  externally (via Google's own OAuth account settings). That is only observable today via a
  future 403 from the affected service's API — there is no proactive revocation check. If
  your integration needs to react to revocation, you have to add that 403-handling path
  yourself; nothing upstream does it for you.

---

## 3. The signed-out contract every new component must honor

Every component in this stack must be safe to call with no Google account connected — it
returns a disconnected/empty/null result and never throws for "not signed in." This is
verified against the shipped code (`docs/GOOGLE_ARCHITECTURE.md` §2 has the file-by-file
detail); your new integration must uphold the same contract:

| Component | Signed-out behavior |
|---|---|
| `GoogleServiceManager` | `initialize()` completes silently, state stays `disconnected`; `clientFor` → `null`; `enableService` → `false`; `disconnect` no-ops. |
| `GoogleAuthRepository` | `silentSignIn()` → `null` (normal, not an error); `signOut()` no-ops; `currentAccessToken()` → `null`. Only `signIn()` ever shows UI, and only when the user taps Connect. |
| `GoogleAccountRepository` | `watchAccounts()` emits `[]`; `getPrimary()` → `null`. |
| `GooglePermissionManager` | cache empty; `hasScopes` → `false`; `ensureScopes` → `notSignedIn`, zero UI. |
| `GoogleApiFactory` | `clientFor` → `null`; no client is ever built without a token. |
| `SyncEngine` | zero channels registered regardless of auth; `flush()` → `SyncReport.idle`. Post-integration: an `authRequired` failure pauses that channel — ops stay pending, exactly like today's dormant queue, never crashes. |
| `ConnectedServicesRepository` | fully functional signed-out (account-independent metadata); Settings shows every service as "Coming soon." |
| `GoogleConnectionState` | `GoogleConnectionState.disconnected()` — a first-class, permanent, non-error state, not a placeholder for an error. |

Net effect: a user who never taps "Connect Google" gets zero prompts, zero network calls to
Google, zero errors, and identical app behavior to before this sprint shipped. Any new
integration that breaks this for the signed-out path is a regression, full stop.

---

## 4. FAQ

**Why can't I just call `GoogleSignIn` directly from my widget?**
Because `lib/platform/google/` is the only directory allowed to import
`package:google_sign_in` — it's an enforced layering rule, not a style preference. Widgets
watch `googleConnectionStateProvider`/`connectedServicesProvider` for state and call
`ref.read(googleServiceManagerProvider)` for actions; `settings_screen.dart`'s Connected
Services section is the existing, working example of this pattern (it imports only
`providers.dart` plus the two pure-domain files). Calling the plugin directly from a widget
would also bypass the connection-state machine, the granted-scope cache, and the 401
feedback loop — none of which the plugin knows how to drive on its own.

**Why is the access token never in the database?**
Because a stored copy would be stale within about an hour (`google_sign_in`/Play services
silently rotates the underlying token) while the existing background sync cadence is 4
hours — a persisted token would almost always be dead by the time anything read it back.
`currentAccessToken()` instead reads the plugin's live `currentUser.authentication` getter
on every call. The one place a stored token would have been *useful* — a headless
WorkManager isolate with no plugin available — is exactly the open problem in §2 (M6),
deliberately not papered over with a token that would already be expired.

**Why does `enableService()` always return `false`?**
Because no product client exists for any `GoogleServiceId` yet — every service is
`comingSoon`. `enableService()` currently just calls
`ConnectedServicesRepository.touchLastUsed(id)` (records that the user tapped the row) and
returns `false`; it deliberately never calls `setStatus()`, because that would fabricate a
`comingSoon → enabled` transition nothing backs. The first sprint that ships a real
integration is also the first sprint that gets to change this method's return value — see
`docs/CONNECTED_SERVICES.md` §4 for exactly what has to change.

**Why does `GooglePermissionManager` have no `GoogleAccountRepository` dependency?**
Because two writers of the same `grantedScopes` column is a real race/drift risk. Instead,
`GoogleServiceManager` is the single writer at rest (via `GoogleAccountRepository.touch()`);
the permission manager only ever holds an in-memory cache, hydrated by the manager at
`initialize()`/`connect()`/`refreshSession()` time.

**Where do I put OAuth scope constants for my new service?**
`lib/platform/google/google_scopes.dart` already has a `GoogleScopes` class with
`tasks`/`calendarEvents`/`driveFile`/`gmailReadonly`/`contactsReadonly` constants — add
yours there rather than inlining a scope string in your integration.
