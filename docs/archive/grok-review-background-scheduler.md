# Grok Review Brief — WorkManager Background Scheduler

**File:** `lib/platform/background/background_scheduler.dart`  
**Status:** Stubs in place, TODO(integration) blocks need implementation  
**Phase:** Phase 1 (no sync, no cloud) — morning refresh + local notification only

---

## What's already wired

- `BackgroundScheduler().init()` calls `Workmanager().initialize(callbackDispatcher)` from `main()` before `runApp`.
- `callbackDispatcher` is a top-level function annotated `@pragma('vm:entry-point')` — tree-shaking safe.
- Two periodic tasks are registered:
  - `neuroflow.morning_refresh` — 24h interval, no network required
  - `neuroflow.sync_flush` — 4h interval, requires network
- The `AndroidManifest.xml` has `FOREGROUND_SERVICE` and `WAKE_LOCK` permissions.

---

## The core problem

`callbackDispatcher` fires in a **new Dart isolate** — not the main app isolate.  
This means:
- No existing `ProviderContainer` from `main()`.
- No widget tree, no `BuildContext`.
- Must manually initialize Flutter bindings + Drift DB.
- Notification service must be re-initialized before sending.

---

## What needs implementing

### `_taskMorningRefresh` (Phase 1 scope)

Goal: send one local notification if there are pending tasks. No-op if empty (no nag).

```dart
case _taskMorningRefresh:
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  try {
    final repo = DriftTaskRepository(db);
    final pending = await repo.watchPending().first;
    if (pending.isNotEmpty) {
      final svc = NotificationService();
      await svc.init();
      await svc.showMorningBriefing(pendingCount: pending.length);
    }
  } finally {
    await db.close();
  }
  break;
```

Requires adding `showMorningBriefing({required int pendingCount})` to `NotificationService`.

### `_taskSyncFlush` (Phase 2 — keep as no-op stub for now)

Leave as `break`. WorkManager gets `true` → no retry. Correct.

---

## Questions for Grok to assess

1. **Isolate safety:** Is creating a fresh `AppDatabase()` in the callback safe when the main isolate's DB may still be alive? Drift uses WAL — is concurrent access from two isolates safe on Android?

2. **Flutter binding in WorkManager isolate:** Does `WidgetsFlutterBinding.ensureInitialized()` work reliably in a WorkManager callback on Android 12+ (Doze, background restrictions)?

3. **Application subclass:** Is `Workmanager().initialize(callbackDispatcher)` from `main()` sufficient, or does the plugin require an Android `Application` subclass to boot the Flutter engine on cold starts?

4. **ExistingWorkPolicy.keep for 24h task:** If the task is delayed by Doze and fires late, is `keep` correct, or should we cancel + re-register to realign the window?

---

## Architecture constraints to preserve

- `callbackDispatcher` stays a **top-level function**.
- `PlanAdvisor.refine()` must NOT be called from background — no Lexi in callbacks.
- No `runApp` or widget APIs in the callback.
- `NotificationService` is a singleton — needs `init()` in the new isolate.

---

## Files to review together

- `lib/platform/background/background_scheduler.dart`
- `lib/platform/notifications/notification_service.dart`
- `lib/data/database.dart`
- `android/app/src/main/AndroidManifest.xml`
