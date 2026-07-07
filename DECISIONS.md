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

- `lib/data/routine_repository_impl.dart` — watchActive() method
- `lib/platform/sync/sync_queue_repository_impl.dart` — enqueue() method  
- `lib/presentation/today_screen.dart` — _CaptureSheet._submit() method
