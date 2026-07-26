# NeuroFlow — Wear OS Companion Spec v1.0
# Target: Pixel Watch 4 (Wear OS 4+)
# Status: DRAFT — pending team review
# Last updated: 2026-06-30

---

## §1  Design Philosophy

The watch is not a second screen for the app. It is a **single-question answerer**:

> "What is the one thing I should do right now?"

Every interaction on the watch must be answerable in under 3 seconds with one thumb tap. ADHD users checking their watch are in motion — waiting for a meeting, walking between tasks, standing in a kitchen. The watch must not require them to stop, read, or decide.

**Hard constraints:**
- No list views. One task at a time, always.
- No input longer than a single tap (no text entry, no voice on watch).
- No settings on the watch. Settings live on the phone.
- Health data (energy logs, mood) never synced to the watch face.

---

## §2  Feature Scope

### In scope (v1)

| Feature | Description |
|---|---|
| Primary task tile | Shows the single primary task from Executive.evaluate() |
| Complete action | One-tap to mark the primary task done; watch vibrates, tile advances to next task |
| "Too hard right now" snooze | Swipe left → snooze 30 min, advances to next quick win |
| Morning briefing complication | Count of pending tasks; tappable to open tile |
| Sync indicator | Subtle dot when phone sync is pending (no action required) |

### Out of scope (v1)

- Habit check-ins on watch (phone only)
- Routine step tracking on watch (phone only)
- Task creation from watch (voice or otherwise)
- Google Tasks sync status on watch
- Any AI suggestions surfaced on watch
- Custom complications beyond pending count

---

## §3  Architecture

### Communication model

Pixel Watch 4 ↔ Pixel 10 Pro XL communicate via the **Wearable Data Layer API** (`com.google.android.gms.wearable`). The phone is always the source of truth.

```
Phone (Flutter app)                  Watch (Wear OS tile + complication)
──────────────────                   ────────────────────────────────────
Executive.evaluate()
    │
    ▼
WearSyncService.push()  ──DataMap──▶  WearDataReceiver
    │                                      │
    │                                      ▼
    │                                 WearStateStore (in-memory)
    │                                      │
    │                                 NeuroFlowTile (renders)
    │                                 NeuroFlowComplication (renders)
    │
    ◀── ChannelClient.sendMessage() ── CompleteAction / SnoozeAction
    │
TaskRepository.markComplete() / snooze()
```

### Data pushed phone → watch

A single `DataMap` keyed at `/neuroflow/primary` containing:

```
taskId:        String   — UUID of the primary task
taskTitle:     String   — display title (truncated to 40 chars on watch)
quickWinCount: Int      — number of quick wins available
pendingCount:  Int      — total pending tasks (for complication)
pushedAt:      Long     — epoch ms (watch ignores stale pushes > 10 min old)
```

No notes, no energy level, no due date. The watch does not need them.

### Messages sent watch → phone

| Path | Payload | Meaning |
|---|---|---|
| `/neuroflow/complete` | taskId: String | User tapped Complete |
| `/neuroflow/snooze` | taskId: String | User swiped "Too hard right now" |

Phone handles both by calling `TaskRepository` and re-running `Executive.evaluate()`, then pushes fresh `DataMap`.

---

## §4  Phone-side: WearSyncService

**File**: `lib/platform/wear/wear_sync_service.dart`

```dart
// Pushes the current primary task to the watch via Wearable Data Layer.
// Called by TodayController after every state change.
// No-ops gracefully if watch is not paired or Data Layer is unavailable.

class WearSyncService {
  static const _kPrimaryPath = '/neuroflow/primary';

  Future<void> pushPrimaryTask(TodayState state) async {
    // TODO(wear/phase1): Wearable.getDataClient().putDataItem(request)
    // Build DataMapRequest from state.primaryTask + state.quickWins.length
    // + pendingCount. Truncate title to 40 chars.
  }

  Future<void> listenForWatchActions({
    required Future<void> Function(String taskId) onComplete,
    required Future<void> Function(String taskId) onSnooze,
  }) async {
    // TODO(wear/phase1): Wearable.getMessageClient().addListener()
    // Route /neuroflow/complete → onComplete
    // Route /neuroflow/snooze  → onSnooze
  }
}
```

**Integration point**: `TodayController.build()` calls `WearSyncService().pushPrimaryTask(state)` after computing `TodayState`. A `WearActionHandler` (started in `main()`) listens for watch messages and calls back into `taskRepositoryProvider`.

---

## §5  Watch-side: Tile

**File**: `wear/src/main/kotlin/dev/neuroflow/NeuroFlowTile.kt`

The tile is a Wear OS 4 `TileService`. It renders the primary task title and two actions: **Done** (green checkmark) and **Too hard** (left swipe / secondary button).

### Tile layout (single-screen, no scroll)

```
┌─────────────────────────────┐
│                             │
│  neuroflow                  │  ← app name, muted
│                             │
│  ████████████████████████   │  ← task title, large, 2-line max
│  ████████████████           │
│                             │
│  [✓ Done]    [→ Skip]       │  ← two action buttons
│                             │
└─────────────────────────────┘
```

Colors: background `#0c0c0d`, title `#e8e8ea`, Done button `#2FB083` (accent), Skip button `#2a2a2e` (surface).

If `pendingCount == 0`: tile shows "You're clear. Rest." — no action buttons.

If `pushedAt` is > 10 minutes old and phone is unreachable: tile shows "Open phone to refresh." — no stale task displayed.

---

## §6  Watch-side: Complication

**File**: `wear/src/main/kotlin/dev/neuroflow/NeuroFlowComplication.kt`

Single complication type: **RANGED_VALUE** (arc) showing pending task count.

- Value: `pendingCount` (0–20, clamped)
- Short text: count as string
- Long text: "tasks left"
- Tap action: opens NeuroFlowTile

Updates whenever phone pushes a new `DataMap`.

---

## §7  Flutter / Kotlin bridge

The watch app is a **separate Wear OS module** in the same Android project (`wear/`). It is Kotlin-only — no Flutter on watch. Flutter on the phone calls into Kotlin via an `AndroidChannel` to trigger Data Layer pushes; the watch module is a standalone Wear OS app that reads from the Data Layer.

**Build note**: `wear/build.gradle` must target `compileSdk 35`, `minSdk 30` (Wear OS 4 minimum). Add `com.google.android.gms:play-services-wearable:18.2.0` to both `android/` and `wear/` modules.

---

## §8  Snooze behavior

"Too hard right now" is not a real snooze in the database sense. On the watch, it means:

1. Phone receives `/neuroflow/snooze` message with `taskId`
2. Phone calls `Executive.evaluate(pending, excluding: taskId)` — excludes that task for this session only (in-memory, `TodayController` holds the exclusion set)
3. The next task in the plan is pushed to the watch
4. The snoozed task reappears on the next `Executive.evaluate()` call (app restart, or next morning refresh)

No database write. No snooze timestamp. Just "show me the next thing."

---

## §9  Privacy

- The DataMap pushed to watch contains **only** task title and counts.
- No notes, no energy level, no health metrics, no habit data.
- Data Layer is local Bluetooth/WiFi between paired devices — does not transit Google servers.
- Cloud Gemini suggestions are never surfaced on the watch.

---

## §10  Open questions (for team discussion)

1. **Snooze duration**: The current design is session-only snooze (no DB write). Should it instead write a `snoozedUntil` timestamp and surface after 30 min? Adds complexity but may be more useful for long tasks.

2. **Complication arc range**: Using 0–20 as the arc range. Should it be 0–`pendingCount` max (dynamic) or fixed? Dynamic makes the arc feel "always full" which could be anxiety-inducing.

3. **Offline tile**: If the phone is out of range, should the tile show the last known task (possibly hours stale) or a "phone out of range" message? Last known task is more useful but could be misleading.

4. **Quick win on watch**: Should the tile be able to cycle through quick wins (secondary swipe) or is one-primary-task-only the right call for v1?

---

## §11  Implementation order

1. Add `wear/` module to Android project, configure `build.gradle`
2. Implement `WearSyncService` on phone (Data Layer push)
3. Implement `NeuroFlowTile` on watch (read DataMap, render, send Complete/Snooze messages)
4. Wire `WearActionHandler` in `main.dart` (listen for watch messages, call repos)
5. Implement `NeuroFlowComplication` (reads same DataMap)
6. Test on Pixel Watch 4 emulator, then real hardware
7. Add to `pubspec.yaml`: no new Flutter deps needed (Data Layer is Android-native)

---

*This spec must be approved before any watch code is written.*
*Tag: neuroflow/wear-os-spec-v1*
