# Bug Fix Decisions — NeuroFlow Phase 1

## BUG 1: Routine Duplication in UI

### Root Cause Analysis
The `watchActive()` method in `lib/data/routine_repository_impl.dart` uses `asyncMap()` to join Routines with their Steps. The problem manifests as routines appearing multiple times in the UI due to:

1. **Stream deduplication issue**: When the Routines table changes, `watchActiveRoutines()` emits a List<RoutineRow>. The `asyncMap` then fetches steps for each routine asynchronously. However, if there are rapid successive changes to the Routines or Steps tables, or if the provider is being watched multiple times, the same routine list can be emitted multiple times.

2. **No step-table watching**: The stream only watches the `Routines` table via `watchActiveRoutines()`. Changes to the `RoutineSteps` table don't trigger a new emission, which can cause stale data or duplicate emissions if the Routines table re-emits.

### Solution
Added manual deduplication logic to the stream using `.where()` to suppress consecutive equal emissions.

**File: `lib/data/routine_repository_impl.dart`**
- Added a `lastEmission` variable to track the previously emitted routine list
- Chained a `.where()` operator after `asyncMap()` to compare routine IDs
- Only emits when the routine list actually changes (ID-based comparison)
- This prevents duplicate emissions even if the source stream re-emits identical data

---

## BUG 2: Task Creation Constraint Error (Silent Failure)

### Root Cause Analysis
The `save()` method in `lib/data/task_repository_impl.dart` enqueues sync operations without proper error handling. The constraint error occurs due to:

1. **Silent error in SyncQueue insertion**: When creating multiple tasks, the second task's sync operation fails during `into(syncQueue).insert()` because:
   - The `insert()` method doesn't use conflict resolution
   - If there's any constraint violation (even if not visible in the schema), the operation fails
   - The error propagates but is never awaited in the UI layer, making it "silent"

2. **Missing conflict resolution**: The `enqueueSyncOp()` method uses `into(syncQueue).insert()` instead of `insertOnConflictUpdate()`. This doesn't handle duplicate insertions gracefully.

3. **Unhandled async error in UI**: The `_CaptureSheet._submit()` method doesn't await `addTask()`, so async errors are unhandled and logged but not shown to the user.

### Solution
Apply two fixes:

**File: `lib/platform/sync/sync_queue_repository_impl.dart`**
- Changed `insert()` to `insertOnConflictUpdate()` to handle potential constraint violations gracefully
- This allows duplicate operations to be replaced rather than causing a constraint error

**File: `lib/presentation/today_screen.dart`**
- Made the task submission async and await the `addTask()` call
- Added error handling to inform the user if task creation fails

---

## Implementation Notes

1. **Minimal surgical fixes**: Only changed the specific methods causing the bugs, no refactoring
2. **Deduplication**: Using Dart's `distinct()` operator from stream operations
3. **Conflict resolution**: Using Drift's `insertOnConflictUpdate()` method for safe insertions
4. **Error visibility**: Adding async/await and error handling in the UI layer

---

## Testing Recommendations

1. **BUG 1 Test**: Create a routine with 2+ steps, then rapidly complete steps and check that duplicates don't appear
2. **BUG 2 Test**: Create two tasks in quick succession and verify both are saved successfully
3. **Monitor**: Watch for any new errors in the sync queue after applying the fix

---

## Files Modified

- `lib/data/routine_repository_impl.dart` — watchActive() method (deduplication)
- `lib/data/habit_repository_impl.dart` — watchActive() method (deduplication)
- `lib/platform/sync/sync_queue_repository_impl.dart` — enqueue() method (error logging)
- `lib/data/database.dart` — enqueueSyncOp() method (conflict resolution)
- `lib/presentation/today_screen.dart` — _CaptureSheet._submit() method (error handling)

---

# Phase 2 STAGE 1: Global Privacy & Health Sync Toggle

## Design Decision: Privacy-First Default

### Rationale
The "Health data sync" toggle defaults to **OFF** for the following reasons:

1. **Privacy-first principle**: Users should never be synced to external health platforms without explicit consent. Health data is the most sensitive data the app handles.

2. **Regulatory alignment**: This default protects HIPAA compliance and similar privacy regulations by requiring affirmative opt-in before any health data leaves the device.

3. **Data minimization**: Users who don't need interoperability with Apple Health / Google Health see no sync attempts, reducing unnecessary external API calls and battery drain.

4. **Clear expectation setting**: Unlike Cloud Gemini (which users may assume is "normal" cloud behavior), health sync is opt-in only, making the user's privacy posture explicit and intentional.

### Where Sync Logic Hooks In (Phase 3)

The toggle gates **permissions only**. The actual sync implementation is deferred to Phase 3:

- **Current scope (Phase 2 STAGE 1)**: Toggle persists to FlutterSecureStorage via SettingsService. Provider wired for reactive state updates across the app. UI placed in "Privacy & Sync" settings section.

- **Phase 3 scope**: Actual data sync logic for Mood Logs will integrate with:
  - **iOS**: HealthKit API via platform channel (requires native Swift bridge)
  - **Android**: Google Fit API via platform channel (requires native Kotlin bridge)

The toggle will act as a guard in Phase 3 when these integrations are built, preventing any sync attempts if `globalPrivacyProvider.state == false`.

### Relationship with Cloud Gemini Toggle

Both toggles follow the same **privacy-critical, opt-in-only** pattern:

| Toggle | Default | Scope | Privacy Model |
|--------|---------|-------|---------------|
| Cloud Gemini | OFF | Task data → Google AI | Opt-in to cloud |
| Health Sync | OFF | Health logs → Apple/Google | Opt-in to external health platforms |

**Difference**: Cloud Gemini is "nice-to-have" (suggestion feature), while Health Sync is "must-have-permission" (interoperability). Both respect user autonomy.

### Files Modified

- `lib/platform/settings_service.dart` — added `getGlobalPrivacyEnabled()` and `setGlobalPrivacyEnabled()` methods
- `lib/presentation/settings_screen.dart` — added "Privacy & Sync" section with "Health data sync" toggle
- `lib/providers.dart` — added `globalPrivacyProvider` as StateProvider<bool>
- `DECISIONS.md` — this entry (documenting design rationale)

---

# Phase 2 STAGE 2: Living-State Tasks & Timeline Integration

## Design Decision: 7-State Task Lifecycle Model

### Why 7 States Instead of 3?

The original 3-state model (pending/completed/skipped) is binary — a task is either "done" or "not done". This doesn't capture the REAL workflow of someone with ADHD, where tasks are:

- **Started but not done** (in progress, paused, blocked, checkpointing)
- **Abandoned mid-execution** (paused for context switch)
- **Stuck waiting** (blocked on external input)
- **Partially complete** (checkpoint reached)

The 7-state model enables:

1. **Progress tracking without binary judgment** — "I did some work" is visible even if incomplete
2. **Re-entry recovery** — paused tasks surface in Phase 3 re-entry card, making it easier to resume
3. **Better prioritization** — blocked tasks sink; in-progress tasks surface; paused tasks available for momentum recovery
4. **Temporal awareness** — the Executive can see task state lifetime and make smarter plan decisions

### State Definitions

| State | Meaning | Transition | UI Implication |
|-------|---------|------------|-----------------|
| **notStarted** | Task created but not touched | user clicks "start" | default state on creation |
| **preparing** | User thinking/planning before execution | user clicks "begin" | pre-execution mental load |
| **inProgress** | Task actively being worked on | user works; can pause/block/checkpoint | primary focus state |
| **paused** | Context switch, interruption, need to context switch | user resumes or moves on | recover via re-entry card (Phase 3) |
| **blocked** | Waiting for external input (reply, resource, decision) | external blocker resolved | sink in priority; may have metadata ("blocked by X") |
| **checkpoint** | Sub-phase complete (intermediate milestone) | user continues or pauses | celebrate progress without finishing |
| **complete** | Task fully finished | terminal state | gone from pending views, tracked in heartbeat |

**State diagram:**
```
notStarted → preparing → inProgress → {paused, blocked, checkpoint} → complete
                              ↓
                           (can jump to paused/blocked from any mid-execution state)
```

### Paused State — Critical for Phase 3

The **paused** state is specifically designed to enable the "re-entry card" feature in Phase 3 STAGE 3. When a user:

1. Starts a task (inProgress)
2. Realizes they need to context switch (hits pause button)
3. Returns to the app later

The app will surface "You were working on X — resume?" via a dedicated re-entry card, powered by searching for paused tasks in the timeline. This is a core ADHD UX pattern — removing friction to resume mid-task work.

### Executive.evaluate() Updates

The planner now:

1. **Distinguishes pending states**: `pending = {notStarted, preparing, inProgress, paused, blocked, checkpoint}`, `complete = {complete}`
2. **Deprioritizes paused tasks by default** — they appear after non-paused quick wins
3. **Surfaces paused tasks if user has momentum** — if other tasks are inProgress, paused tasks become quick-win candidates (Phase 3 momentum heuristic)
4. **Never shows paused as a terminal state** — it's always recoverable

### Timeline as Read-Only Projection

**Critical rule: NO NEW DATABASE TABLE** (§4, Timeline Rule).

The timeline is a **computed stream** that merges existing data:

- **Tasks**: Emit `taskCreated` event at `task.createdAt`, `taskCompleted` event at `task.completedAt` (if complete)
- **Routines**: Emit `routineStarted` at `routine.createdAt`, `routineCompleted` when all steps done (heuristic time in Phase 2; real timestamp in Phase 3)
- **Habits**: Emit `habitChecked` for each check-in, keyed to `checkIn.createdAt`

All merging happens in `timelineProvider` — a single StreamProvider that:
1. Watches taskRepositoryProvider.watchPending()
2. Watches activeRoutinesProvider
3. Watches activeHabitsProvider
4. Combines all three into a List<TimelineEvent>
5. Sorts by timestamp (most recent first)
6. Emits as a read-only stream

**Why no table?**
- Timeline events are derived (not primary data)
- Timestamps already exist in Task, Routine, Habit, and HabitCheckIn
- Computing in memory is cheaper than joins and reduces schema complexity
- If timeline data needs persistence later (archival, export), use the source events, never raw timeline rows

### Timestamp Derivation (Phase 2 Heuristics)

| Event Type | Timestamp Source |
|------------|-----------------|
| taskCreated | task.createdAt |
| taskCompleted | task.completedAt |
| routineStarted | routine.createdAt |
| routineCompleted | routine.createdAt + 1 hour (Phase 2 heuristic; Phase 3 captures real completedAt) |
| habitChecked | checkIn.createdAt |
| moodLogged | mood.createdAt (future feature; mood domain exists but not wired yet) |

### Files Modified

- `lib/domain/task.dart` — migrated TaskStatus to 7-state enum; added completedAt field; updated domain helpers
- `lib/domain/timeline_event.dart` — NEW; domain models for all timeline event types
- `lib/platform/local/database.dart` — updated openTasks(), watchOpenTasks(), untouchedFor(), and watchCompletedTodayCount() to use new TaskStatus states
- `lib/platform/local/task_repository_impl.dart` — updated complete() and archive() to use new states
- `lib/executive/planner.dart` — updated Executive.evaluate() to work with 7-state model; added paused task recovery heuristic
- `lib/providers.dart` — added timelineProvider (StreamProvider<List<TimelineEvent>>); added helper functions _taskStatusLabel() and _energyLabel()
- `DECISIONS.md` — this entry

### Phase 3 Notes — Future Work

#### Timeline View UI
Not implemented in Phase 2. Phase 3 STAGE 1 will create:
- TimelineScreen showing chronological activity feed
- Event cards (task, routine, habit, mood)
- Filtering by event type
- Date grouping (today, this week, older)

#### Re-Entry Card
Phase 3 STAGE 3 will use paused tasks from timeline to power:
- "You were working on X — resume?" card on Today screen
- Auto-suggests paused task if user revisits within 24 hours
- One-tap resume (returns task to inProgress)

#### Mood Log Integration
Mood domain exists (`lib/domain/mood.dart`) but MoodRepository is not wired. Phase 3 will:
- Create MoodRepository + Drift implementation
- Wire moodRepositoryProvider
- Emit MoodEvent from timeline when moods logged
- Timeline view shows mood events (color-coded)

#### Captured Timestamp for Routines
Phase 2 uses heuristic (createdAt + 1 hour) for routine completion. Phase 3 will:
- Add completedAt field to Routine domain
- Capture actual time when last step completed
- Update database schema (Routines table)
- Update timeline to use real timestamp

### Backward Compatibility

Existing tasks with status=pending migrate to status=notStarted automatically (Drift migration in Phase 3). The `isPending` computed property works with the new model:

```dart
bool get isPending => status != TaskStatus.complete;
```

This means old code filtering for `isPending` continues to work with new states.

---

# Phase 2 STAGE 3: Re-Entry Card

## Design Decision: Progress-First Re-Entry UI for Paused Tasks

### Purpose

The Re-Entry Card is an ADHD-friendly feature that surfaces paused tasks with minimal friction. When a user returns to the app after context-switching, a single card offers:

1. **Progress celebration** — show the work already done ("60% progress")
2. **Context recall** — remind them where they paused ("Paused at: Step 4")
3. **Micro-action suggestion** — one small next step ("Next: Check logs")

This follows ADHD-friendly UX patterns:
- **Progress-first messaging**: Show wins before asking for more effort
- **Context preservation**: Exact checkpoint reduces re-orientation time
- **Minimal friction**: One tap to resume; one tap to dismiss

### Architecture: No Database Changes

The Re-Entry Card uses **existing Task fields only**:
- `status = TaskStatus.paused` (already defined in Phase 2 STAGE 2)
- `notes` (existing field — parsed heuristically in Phase 2)
- `title` (used to infer next action)
- `createdAt` (used to sort paused tasks by recency)

**No new tables, no new columns.** Phase 3 will add persistent step tracking if needed; Phase 2 uses best-effort heuristics.

### Phase 2 Heuristics

The `ReentryAdvisor` class analyzes a paused task using simple pattern matching:

1. **Progress percentage**: Count newline-delimited lines in task.notes
   - 1 line → 25%
   - 2-3 lines → 50%
   - 4-5 lines → 60%
   - 6+ lines → 75% (capped below 100% until task marked complete)

2. **Paused-at step**: Extract the last line of task.notes
   - Strips leading numbers/bullets ("1. Step" → "Step")
   - Wrapped in quotes: `Paused at: "Step 4: Deploy"`

3. **Suggested action**: Pattern match on task title verbs
   - "Deploy X" → "Check logs"
   - "Review PR" → "Merge if approved"
   - "Write email" → "Send reply"
   - "Setup X" → "Test it"
   - Default: "Continue"

**Phase 2 limitation**: These are estimates. A user might have completed 2 of 5 steps, but if they only wrote 2 notes lines, progress shows ~50% instead of 40%. The heuristic favors showing progress.

### Phase 3 Future: Real Step Tracking

Phase 3 STAGE 3 will:

1. Add `SubtaskCompletion` table in database (tracks which subtasks are done)
2. Compute real progress: `(completed / total) * 100`
3. Replace title/notes parsing with actual step metadata
4. Enable richer context: "Step 4 of 8 done" instead of "60% progress"

### UI: Re-Entry Card Placement

The card appears in the Today screen's normal mode, **above the primary task**:

```
[Header: Hey, User | Count: 7]
─────────────────────────────────
[Re-Entry Card — paused task]
─────────────────────────────────
[Primary Task Card]
─────────────────────────────────
[Due Routines / Habits]
```

**Visibility logic**:
- Show only if `pausedTasks` list is non-empty
- Show only the **top 1 paused task** (most recent)
- Use `snoozeForSession()` for dismiss (visual only; no DB change)
- Use `resumePausedTask()` for resume (transitions paused → inProgress)

### Components

**File: `lib/executive/reentry_advisor.dart`**
- `ReentryAdvisor` class — analyzes paused tasks
- `ReentryData` class — holds progress %, paused-at step, suggested action
- Private helpers: `_extractSteps()`, `_estimateProgress()`, `_extractPausedAtStep()`, `_suggestAction()`

**File: `lib/presentation/widgets/reentry_card.dart`**
- `ReentryCard` StatelessWidget — renders the UI
- Layout: header (pause icon + title) → progress bar → context → action → buttons
- Colors: AppColors.accent border, AppColors.surface fill (matches other cards)
- Buttons: "← Go back" (dismiss) | "Resume →" (resume)

**File: `lib/providers.dart`**
- `pausedTasksProvider` — FutureProvider that filters pending tasks for status=paused
- `TodayController.resumePausedTask()` — transitions paused → inProgress and recomputes plan

**File: `lib/presentation/today_screen.dart`**
- Updated `_NormalBody` to watch `pausedTasksProvider` and show card if available
- Wired resume/dismiss buttons to controller methods

### Dismissal Behavior

The "← Go back" button calls `snoozeForSession()`, which:
- Adds task ID to `_snoozedIds` set in TodayController
- Invalidates the provider to trigger rebuild
- **Does not** modify database — dismissal is session-local only
- Card reappears if user restarts the app (re-entry still available)

**Rationale**: Users may want to dismiss the card without actually resuming, but we should re-prompt on next session if the task remains paused. Session-only snooze gives immediate UI relief without losing the re-entry opportunity.

### Files Modified

- `lib/executive/reentry_advisor.dart` — NEW; advisory logic for paused tasks
- `lib/presentation/widgets/reentry_card.dart` — NEW; UI component
- `lib/presentation/today_screen.dart` — added ReentryCard widget, imported it, updated _NormalBody to ConsumerWidget
- `lib/providers.dart` — added `pausedTasksProvider`, added `resumePausedTask()` method to TodayController
- `DECISIONS.md` — this entry

### Testing Notes

1. **Create a paused task**: Create a task, mark it inProgress, then manually change status to paused (via DB query in test)
2. **Verify progress estimation**: Add notes with 3-5 lines, verify progress shows ~50-60%
3. **Verify action suggestion**: Create a task titled "Deploy database", verify suggested action is "Check logs"
4. **Test resume flow**: Tap "Resume →", verify task transitions to inProgress and re-entry card disappears
5. **Test dismiss flow**: Tap "← Go back", verify card hides (but stays in DB as paused, re-appears on app restart)

---

# Google Foundation Sprint — Stages 4-5: Authentication + GoogleServiceManager

Implements `STAGE2_COMPONENT_DESIGN.md` §2.1-2.4, §2.6-2.7, §3-5 (design doc, revision 2
post adversarial-critic review). Full architecture diagram and component specs live in
that document; this entry records the binding decisions and the deviations this
implementation stage had to make.

## Decision: tokens never live in Drift

`GoogleAccounts` (schema v5) stores account METADATA only — id, email, displayName,
photoUrl, grantedScopes (space-separated string), isPrimary, connectedAt,
lastRefreshAt, tokenExpiresAtEstimate. No column holds a token, and none ever will;
adding one is a review-blocking regression. Access tokens are never persisted anywhere
(see next decision); the ID token is the only token FlutterSecureStorage ever holds,
under a per-account key `neuroflow_google_id_token_<accountId>`, written and deleted
exclusively by `GoogleSignInAuthRepository` (`lib/platform/google/google_auth_repository_impl.dart`).

## Decision: `tokenExpiresAtEstimate` is derived, never plugin-provided

`google_sign_in` v6.2.1 exposes no token-expiry field — `GoogleSignInAuthentication`
surfaces only `accessToken` / `idToken` / `serverAuthCode`. `GoogleAccount.estimateExpiry()`
derives it as `(lastRefreshAt ?? connectedAt) + 55min`, deliberately shy of the ~60-minute
access-token TTL to absorb device clock skew. It is advisory-only — used to hint a
"may need to reconnect" state in a future Settings UI — and is NEVER used to gate
`GoogleApiFactory.clientFor()` and NEVER itself flips `GoogleConnectionStatus` to
`expired`. The authoritative expiry signal is a live 401 from an API call.

## Decision: `currentAccessToken()` reads the plugin's live getter, never storage

`GoogleAuthRepository.currentAccessToken()` (impl: `GoogleSignInAuthRepository`) reads
`GoogleSignIn.currentUser.authentication` fresh on every call — it never reads a stored
copy. A secure-storage copy would be stale within about an hour (the plugin/Play
Services silently rotates the underlying token), which is the common case given the
existing 4h WorkManager sync cadence. This is also why the design does not persist an
access token at all: the one place a stored copy would have been useful — a headless
WorkManager isolate flushing Google-backed sync without the plugin available — is an
open problem explicitly deferred to the tasks-integration sprint (not papered over with
a token that would already be stale).

## Decision: `switchAccount` is descoped this sprint

`GoogleServiceManager` has no `switchAccount` method. `google_sign_in` ^6.2.1 has no
account-targeted silent sign-in (only one `currentUser` at a time), and this sprint's
Settings surface has no multi-account UI to call it. `GoogleAccountRepository` still
supports N accounts and `setPrimary` (cheap, future-proof), but nothing but the first-
connected account is ever made primary this sprint. A future multi-account sprint would
respecify `switchAccount` as an interactive `signIn()` whose returned account is
compared against the requested id, not a silent targeted restore.

## Decision: `connecting → expired` is a legal transition

`GoogleConnectionState.isLegalTransition()` allows `connecting → expired` in addition to
`connecting → {connected, error, disconnected}`. This covers `GoogleServiceManager.initialize()`:
a previous session existed (a persisted `GoogleAccountRepository` row) but the plugin's
`silentSignIn()` could not restore it — distinct from `connecting → error`, which is
reserved for an unexpected plugin/network exception. Without this transition,
`initialize()`'s own documented behavior would trip the manager's debug-mode transition
assert on a legitimate, non-exceptional path.

## Decision: 401 feedback via `notifyAuthFailure()`

`GoogleApiFactory`'s `_AuthenticatedClient` (an `http.BaseClient`) reads the token via
`GoogleAuthRepository.currentAccessToken()` at `send()` time and, on a 401 response,
invokes an injected `onAuthFailure` callback exactly once — wired to
`GoogleServiceManager.notifyAuthFailure()` at composition-root time (`providers.dart`).
`notifyAuthFailure()` transitions `connected → expired` and fires one best-effort silent
`refreshSession()`. This is the only path that reaches `GoogleConnectionStatus.expired`
from live traffic in practice; proactive expiry detection via `tokenExpiresAtEstimate`
is deliberately not attempted (see above).

## Implementation deviation: `GoogleApiFactory`'s auth-failure callback is wired via a
## post-construction setter, not a constructor argument

`GoogleServiceManager` depends on `GoogleApiFactory`, and `GoogleApiFactory` needs a
callback into `GoogleServiceManager.notifyAuthFailure()` — a naive constructor-time
wiring is circular in the Riverpod provider graph (`googleServiceManagerProvider` would
need to read itself via `googleApiFactoryProvider`). Resolved with
`GoogleApiFactory.wireAuthFailureCallback(void Function())`, called once by
`googleServiceManagerProvider` immediately after both objects are constructed; the
factory stores it behind a trampoline closure so clients created before or after the
wiring call still pick up the current callback. The provider-table row in
STAGE2_COMPONENT_DESIGN.md §4 (`GoogleApiFactoryImpl(authRepo, permissionManager)`, no
third constructor arg) is consistent with this — the design doc's class-body pseudocode
just didn't spell out the wiring mechanism.

## Implementation deviation: ConnectedServicesRepository / SyncEngine dependencies
## dropped from `GoogleServiceManager` this stage

STAGE2_COMPONENT_DESIGN.md §2.1 specs `GoogleServiceManager`'s constructor with six
dependencies, including `ConnectedServicesRepository` and `SyncEngine`, and an
`enableService()` method that writes through the former. This implementation stage
(Stages 4-5, Authentication + GoogleServiceManager only) is explicitly scoped to NOT
build `ConnectedServicesRepository` — that ships in a parallel Stage 6/7 task.
`GoogleServiceManager` here therefore takes only `GoogleAuthRepository`,
`GoogleAccountRepository`, `GooglePermissionManager`, and `GoogleApiFactory`, and does
not implement `enableService()`. `registerServiceIntegration()` and `clientFor(GoogleServiceId)`
ARE implemented — the registration seam itself needs only an in-memory
`Map<GoogleServiceId, GoogleServiceIntegration>`, no `ConnectedServicesRepository` or
`SyncEngine` — so the seam is real, just unpopulated (nothing registers an integration
this sprint). `lib/domain/google_service.dart` accordingly ships only the
`GoogleServiceId` enum this stage, not the `GoogleServiceStatus` / `ConnectedService`
domain types that belong to `ConnectedServicesRepository`. The `GoogleAccounts` v4→v5
migration is likewise scoped to that one table — the design doc's combined
`GoogleAccounts` + `ConnectedServices` migration is split across the two parallel tasks
to avoid both touching `schemaVersion`/`onUpgrade` at once; whichever lands second bumps
to v6. `syncEngineProvider` already exists in `providers.dart` from the parallel
SyncEngine task and is untouched here; `connectedServicesRepositoryProvider`,
`connectedServicesProvider`, and `syncProgressProvider` are left for that follow-up work
(one-line pointer comments only, no stub providers).

## Files Modified / Created

- `lib/domain/google_account.dart` — NEW; `GoogleAccount` metadata model (no tokens)
- `lib/domain/google_connection_state.dart` — NEW; `GoogleConnectionStatus` enum + `GoogleConnectionState`, including `isLegalTransition()`
- `lib/domain/google_service.dart` — NEW; `GoogleServiceId` enum only (see deviation above)
- `lib/data/google_auth_repository.dart` — NEW; `GoogleAuthRepository` interface + `GoogleAuthException`/`GoogleAuthTokenExpiredException`
- `lib/data/google_account_repository.dart` — NEW; `GoogleAccountRepository` interface
- `lib/data/google_account_repository_impl.dart` — NEW; `DriftGoogleAccountRepository`, enforces the single-primary invariant via `AppDatabase.transaction()`
- `lib/data/database.dart` — added `GoogleAccounts` table (schema v4 → v5, additive `onUpgrade`), low-level query primitives (`watchGoogleAccounts`, `fetchGoogleAccounts`, `upsertGoogleAccount`, `demoteAllGoogleAccounts`, `promoteGoogleAccount`, `touchGoogleAccount`, `removeGoogleAccount`, `clearGoogleAccounts`)
- `lib/platform/google/google_auth_repository_impl.dart` — NEW; `GoogleSignInAuthRepository`
- `lib/platform/google/google_permission_manager.dart` + `google_permission_manager_impl.dart` — NEW; `GooglePermissionManager` / `GooglePermissionManagerImpl` (no `GoogleAccountRepository` dependency)
- `lib/platform/google/google_api_factory.dart` + `google_api_factory_impl.dart` — NEW; `GoogleApiFactory` / `GoogleApiFactoryImpl`, `_AuthenticatedClient`
- `lib/platform/google/google_service_manager.dart` — NEW; `GoogleServiceManager` facade, `GoogleServiceIntegration`
- `lib/platform/google/google_scopes.dart` — NEW; unused-this-sprint `GoogleScopes` constants
- `lib/providers.dart` — added `googleSignInPluginProvider`, `googleAuthRepositoryProvider`, `googleAccountRepositoryProvider`, `googlePermissionManagerProvider`, `googleApiFactoryProvider`, `googleServiceManagerProvider`, `googleConnectionStateProvider`
- `lib/main.dart` — added non-blocking, try/catch-wrapped `googleServiceManagerProvider.initialize()` call at startup (silent session restore)
- `DECISIONS.md` — this entry

---

# Google Foundation Sprint — Stage 6: Connected Services Settings Page

Implements `STAGE2_COMPONENT_DESIGN.md` §2.8, the remaining half of §2.1 (`ConnectedServicesRepository`
dependency + `enableService()`), and §3-4 (the split-in-two `ConnectedServices` migration and its
providers) that the Stages 4-5 entry above explicitly deferred to this task. `SyncEngine` — the other
dependency §2.1 lists on `GoogleServiceManager` — is deliberately still not wired in; nothing in this
facade consumes it yet and the parallel Stage 7 SyncEngine keeps its own independent provider.

## Decision: schema v5 → v6, additive only, does not touch the v5 GoogleAccounts block

Per the note left in the Stages 4-5 entry ("whichever lands second bumps to v6"), this task bumps
`AppDatabase.schemaVersion` from 5 to 6 and adds a `ConnectedServices` table via a new
`if (from < 6) { await m.createTable(connectedServices); }` block appended after (never merged into)
the existing `if (from < 5)` block. No changes to `GoogleAccounts` or any other v5-and-earlier table.

## Decision: `ConnectedServices` rows are seeded via an explicit, awaited `ensureSeeded()` step — never lazily inside `watchAll()`'s stream pipeline

The design doc originally specified lazy seeding "on first read" inside the watch stream.
`STAGE2_CRITIC_REPORT.md` m5 flagged this as a write-triggers-rewatch risk: a table write performed
during stream setup re-fires the same Drift watcher that triggered it. Fix shipped here:
`DriftConnectedServicesRepository` kicks off a `Future<void> _seeded` (an idempotent
"insert one comingSoon row per missing `GoogleServiceId`" pass) once in its constructor; every public
method (`watchAll()`, `get()`, `setStatus()`, `touchLastUsed()`, `clearAll()`) `await`s that same Future
before touching the table, and the write itself never happens inside `watchConnectedServices()`'s
`.watch()` pipeline. `clearAll()` re-runs the same idempotent seed pass immediately after wiping the
table, so the "always exactly one row per `GoogleServiceId`" invariant holds immediately after a
factory reset too, not just at cold start.

## Decision: `enableService()` "records intent" means `touchLastUsed()`, not `setStatus()`

`STAGE2_CRITIC_REPORT.md` n3 flagged the design doc's "records intent via ConnectedServicesRepository
(status stays comingSoon)" as ambiguous — recording *what*, concretely? Resolved: a tap on a
"coming soon" service row calls `GoogleServiceManager.enableService(id)`, which calls
`ConnectedServicesRepository.touchLastUsed(id)` (sets `lastUsedAt`) and always returns `false`. It
never calls `setStatus()` — `status` is reserved for a real state transition
(`comingSoon → available/enabled/disabled`) that only a future sprint with an actual product client
may perform; writing `status` here would fabricate a status change nothing backs. `lastUsedAt` is a
timestamp-only signal that costs nothing and gives a future sprint usage data ("which coming-soon
services did users tap") without pretending anything was enabled.

## Decision: no snackbar / visible feedback on a "coming soon" tap

Tapping a coming-soon service row calls `enableService()` fire-and-forget and renders nothing new —
no snackbar, no dialog, no toggle animation (the `Switch` is rendered disabled via `onChanged: null`,
wrapped in `IgnorePointer` so taps pass through to the row's `InkWell` instead of being swallowed).
This is a deliberate ADHD-friendly UX choice: an action with no real effect should not manufacture a
dead-end feedback loop or a false sense of progress.

## Deviation: `GoogleServiceManager` gains only `ConnectedServicesRepository`, not `SyncEngine`

STAGE2_COMPONENT_DESIGN.md §2.1's six-dependency constructor also lists `SyncEngine`. This task adds
only the fifth dependency, `ConnectedServicesRepository` — `SyncEngine` is intentionally left out.
Nothing in `GoogleServiceManager`'s current surface (connect/disconnect/refreshSession/enableService/
clientFor) needs a sync engine; `syncEngineProvider` already exists in `providers.dart` from the
parallel Stage 7 task and is untouched here. Wiring `SyncEngine` into the facade is left for whichever
future sprint actually registers a sync channel through it.

## Files Modified / Created

- `lib/domain/google_service.dart` — added `GoogleServiceStatus` enum and `ConnectedService` class (extends the Stages 4-5 `GoogleServiceId`-only file; no second domain file, per design §2.8's single-file layout)
- `lib/data/connected_services_repository.dart` — NEW; `ConnectedServicesRepository` interface (`watchAll`, `get`, `setStatus`, `touchLastUsed`, `clearAll`)
- `lib/data/connected_services_repository_impl.dart` — NEW; `DriftConnectedServicesRepository`, with the constructor-kicked-off `_seeded` Future fix for m5 described above
- `lib/data/database.dart` — added `ConnectedServices` table (`@DataClassName('ConnectedServiceRow')`), bumped `schemaVersion` 5 → 6, added the additive `if (from < 6)` migration block, added low-level query primitives (`watchConnectedServices`, `fetchConnectedServices`, `upsertConnectedService`, `patchConnectedService`, `clearConnectedServices`) mirroring the existing `GoogleAccounts` primitives
- `lib/platform/google/google_service_manager.dart` — added `ConnectedServicesRepository services` constructor dependency; implemented `enableService(GoogleServiceId)` per the decision above
- `lib/providers.dart` — added `connectedServicesRepositoryProvider` and `connectedServicesProvider` in a new delimited block; updated the existing `googleServiceManagerProvider` block with one added line (`services: ref.watch(connectedServicesRepositoryProvider)`) rather than rewriting it
- `lib/presentation/settings_screen.dart` — added a "Connected Services" section: `_GoogleAccountTile`/`_GoogleAccountCard` (watches `googleConnectionStateProvider`; the sprint's only functional action, `connect()`/`disconnect()`) and `_MoreServicesList`/`_ComingSoonServiceTile`/`_ComingSoonBadge` (watches `connectedServicesProvider`; every row inert this sprint). Imports only `domain/google_connection_state.dart` and `domain/google_service.dart` (pure domain) plus `providers.dart` — no `google_sign_in`, no `lib/platform/google/*` import.
- `DECISIONS.md` — this entry

---

# Google Foundation Sprint — QA fix: `_reconcile()` grantedScopes is a union, not "fresh wins"

## Bug

`GoogleSignInAuthRepository._toAccount()` (`lib/platform/google/google_auth_repository_impl.dart`)
always sets `grantedScopes: const ['email', 'profile']` — the base sign-in scopes are all the
auth layer ever knows about; anything beyond that is `GooglePermissionManager`'s cache, by
design (the auth repo deliberately does not depend on it). Because `fresh.grantedScopes` is
therefore *never* empty, `GoogleServiceManager._reconcile()`'s old
`fresh.grantedScopes.isNotEmpty ? fresh.grantedScopes : existing.grantedScopes` always took the
`fresh` branch — the `existing` branch was permanently dead code. Harmless today (nothing this
sprint calls `GooglePermissionManager.ensureScopes()` beyond email/profile — see
STAGE2_COMPONENT_DESIGN.md §7 non-goals), but the moment a future sprint persists an
incrementally-granted scope (e.g. Tasks) via `GoogleAccountRepository.touch(grantedScopes: ...)`,
every subsequent `initialize()` (silent restore) or `refreshSession()` call would silently
overwrite the persisted extra scope back down to just `['email', 'profile']`, since `_reconcile()`
would trust `fresh` and `_persistAndHydrate()` writes the result straight back through.

## Fix

`_reconcile()` now computes `grantedScopes` as the **union** of `fresh.grantedScopes` and
`existing.grantedScopes` instead of picking one or the other. `_toAccount()` is not made to lie
about scopes it doesn't know it has — the union lives in `_reconcile()`, the one place that
already sees both the freshly-reported base scopes and whatever was previously persisted. This
is deliberately conservative: it never lets a base-scope-only result drop a previously-granted
extra scope, at the cost of not handling scope *revocation* (a scope removed via Google's OAuth
settings, detectable today only via a future 403 from that service's API — a known separate gap,
m2 in `STAGE2_CRITIC_REPORT.md`, not addressed by this fix). All three call sites
(`initialize()`, `connect()`, `refreshSession()`) pass `fresh` from the auth repository and
`existing` from `GoogleAccountRepository` unchanged, so the union is a strict superset of the old
(effectively fresh-only) behavior in every case — none of them regress.

### Files Modified

- `lib/platform/google/google_service_manager.dart` — `_reconcile()`: `grantedScopes` computed as
  `{...existing.grantedScopes, ...fresh.grantedScopes}.toList()` instead of the dead-branch
  `isNotEmpty` check
- `DECISIONS.md` — this entry

## Decision: Stage 8 security-audit fixes

- `lib/platform/sync/sync_queue_repository_impl.dart` — `enqueue()`'s catch block no longer
  interpolates the caught exception into `print()`; `SyncOperation` carries task content
  (taskTitle/taskNotes/googleTaskId) and a Drift/sqlite3 exception's `toString()` can embed bound
  statement values, so the log line now emits only `e.runtimeType`, matching the fixed-category
  sanitization pattern already used in `google_service_manager.dart`/`google_auth_repository_impl.dart`.
- `docs/GOOGLE_SETUP.md` — replaced the two committed real-email examples (`starwolf0007@gmail.com`,
  "User support email" §2 and "test users" §2) with the placeholder `<your-dev-email>`.

## Decision: LexiPlanAdvisor moves to lib/intelligence/, real AICore wiring (supersedes prior draft)

A more complete Lexi/AICore implementation (Dart + Kotlin) was provided to replace an earlier
first-pass draft. Auditing it against this repo's actual code surfaced two real gaps between the
new files and this codebase's current state, both fixed before wiring in:

1. **`Plan.copyWith()` did not exist.** The new advisor calls it repeatedly (`plan.copyWith(reason:
   ...)`, `plan.copyWith(primaryTask: ..., reason: ...)`, `plan.copyWith(quickWins: ..., reason:
   ...)`). Added to `lib/executive/planner.dart` covering this repo's actual four `Plan` fields
   (`mode`, `primaryTask`, `quickWins`, `reason`) — `mode` is deliberately NOT overridable via
   `copyWith`, since changing mode is a Plan-*selection* decision that must stay deterministic;
   only order/reason are AI-influenced (see below).
2. **`Task.estimatedMinutes` did not exist** on this repo's `Task` domain model (confirmed:
   `id, title, notes, energy, status, createdAt, dueDate, completedAt, isQuickWin` — no duration
   field). The incoming `lexi_config.dart` referenced `t.estimatedMinutes` in its prompt builder —
   removed rather than added as a new persisted field, since introducing one would be a schema
   change (Drift migration, repository, provider updates) far outside the scope of wiring up Lexi.
   The provided files' own handoff notes mention a "returnable list" field on `Plan` that likewise
   doesn't exist in this codebase — evidence the incoming files were authored against a different
   snapshot of the project; adapted rather than blindly applied.

### Architectural relocation: `LexiPlanAdvisor` and `LexiConfig` move from `lib/executive/` to
`lib/intelligence/`

Both files' own headers declared their new home as `lib/intelligence/`, and the move is correct:
`LexiPlanAdvisor` imports `dart:convert` and `package:flutter/services.dart` (a platform channel) —
concerns the Executive layer must never own (per this repo's own architecture rule: Executive stays
AI/platform-agnostic; `PlanAdvisor` is the seam interface, defined in `lib/executive/planner.dart`,
implemented by AI-aware code living in `lib/intelligence/`). This mirrors the existing
interface-in-one-layer / impl-in-another pattern used everywhere else in this codebase (e.g.
`TaskRepository` interface in `lib/data/`, Drift impl alongside it; `GoogleAuthRepository` interface
in `lib/data/`, plugin-binding impl in `lib/platform/google/`). `lib/executive/lexi_plan_advisor.dart`
was deleted; `lib/intelligence/lexi_plan_advisor.dart`, `lib/intelligence/lexi_config.dart` (moved
from `lib/executive/`), and a new `lib/intelligence/planning_context.dart` (typed prompt-context
snapshot, avoids ad-hoc string building at call sites) take its place. `providers.dart`'s import
updated accordingly; `LexiPlanAdvisor()`'s zero-arg construction site is unaffected.

### `lib/intelligence/lexi_bridge.dart` removed (superseded, not kept as dead code)

An earlier draft added a standalone `LexiBridge` Dart wrapper class (`isAvailable()`/`ping()`/
`generate()`) that `LexiPlanAdvisor` called through. The new `lexi_plan_advisor.dart` owns its own
channel calls directly (`_checkAvailabilityNative()`/`_generate()`), matching the original
pre-existing code shape and the native side's own contract doc ("must match
lib/intelligence/lexi_plan_advisor.dart exactly"). Keeping the old wrapper around unused would leave
two independent implementations of the same channel call — deleted rather than left as a trap.

### Kotlin: `LexiBridge.kt` reimplemented against AICore's documented exp01 surface

Replaces the always-`false`/always-`null` stub (and an earlier draft's `.candidates.firstOrNull()?.text`
guess) with `GenerativeModel.generateContent(prompt).text` — the exp01 reference's actual response
shape — plus:
- `prepareInferenceEngine()` success as the availability signal (never triggers a model download —
  a multi-GB silent fetch would violate this app's calm/no-surprise principle; not-yet-downloaded
  reports as unavailable, same as any other ineligible-device case).
- Two independent 5-second timeouts: Kotlin's `withTimeout(5_000L)` around inference (surfaced as
  `PlatformException("LEXI_TIMEOUT")`), and Dart's own `.timeout()` around the whole channel
  round-trip (covers channel latency and any native path that forgets its own timeout). Both land
  on the identical "return plan unchanged" path.
- Runtime-gated at `Build.VERSION.SDK_INT >= 34` (Android 14 QPR1, AICore's actual system-service
  floor) rather than raising the app's `minSdk` — see `lib/intelligence/GRADLE_AICORE_SETUP.md`,
  which also documents the separate `minSdk 31` *compile/install* floor the AI Edge SDK itself
  requires (two different numbers, two different jobs: install floor vs. runtime feature gate).
- Channel method names kept as `checkGeminiNanoAvailable`/`generateResponse` (not renamed to
  `isAvailable`/`generate`) — that contract was already established and verified across both Dart
  and Kotlin; renaming would be pure churn with no benefit.

### AndroidManifest.xml: `<uses-feature android:name="android.software.ai_capabilities"
android:required="false"/>` added

Supersedes this repo's prior position (documented in an earlier commit) that no manifest feature
declaration was needed. `required="false"` keeps the app installable on every device (Play Store
never filters it out); it declares interest in on-device AI without gating install eligibility,
while `LexiBridge`'s own `SDK_INT >= 34` + `prepareInferenceEngine()` runtime check remains the real
availability gate. No new `<uses-permission>` — AICore has no runtime permission, and inference is
on-device (no network call).

### Reordering contract (unchanged in spirit, restated precisely for the new code)

Lexi may reorder within the Executive's own candidate set (`primaryTask` in normal mode is
replaceable only by an exact/case-insensitive title match already present in `allPending`;
`quickWins` may be reordered only among tasks already in that list) and may reword `reason`. She may
never introduce a task absent from `allPending`, and can never change `plan.mode`. An unmatched or
hallucinated `taskTitle` is discarded silently, identical to any other malformed-response case.

### Files Modified / Created

- `lib/executive/planner.dart` — added `Plan.copyWith()` (mode excluded, see above)
- `lib/executive/lexi_plan_advisor.dart` — deleted (moved, see below)
- `lib/executive/lexi_config.dart` — deleted (moved to `lib/intelligence/`)
- `lib/intelligence/lexi_bridge.dart` — deleted (superseded, see above)
- `lib/intelligence/lexi_plan_advisor.dart` — new location; full advisor incl. fence-tolerant JSON
  parsing, exact/case-insensitive task-title resolution, airtight fallback chain
- `lib/intelligence/lexi_config.dart` — new location; system prompt updated to the
  `{taskTitle, reason}` contract, `buildPrioritizationPrompt()`; `estimatedMinutes` reference
  removed (field doesn't exist in this repo — see above)
- `lib/intelligence/planning_context.dart` — new; typed prompt-context snapshot
- `lib/intelligence/GRADLE_AICORE_SETUP.md` — new; exact Gradle dependency + minSdk reasoning +
  manifest snippet + device-support table (this repo's `android/app/build.gradle` still doesn't
  exist — this doc is what to apply once it does)
- `lib/intelligence/README.md` — status updated (Android side implemented, pending Gradle scaffold;
  iOS not started)
- `android/app/src/main/kotlin/com/neuroflow/lexi/LexiBridge.kt` — reimplemented against AICore
- `android/app/src/main/AndroidManifest.xml` — added `<uses-feature>` (see above)
- `lib/providers.dart` — import path updated for `LexiPlanAdvisor`'s new location
