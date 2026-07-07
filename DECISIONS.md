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
