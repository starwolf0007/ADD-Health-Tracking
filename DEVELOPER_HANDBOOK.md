# NeuroFlow — Developer Handbook

*Onboarding for a new engineer. Get from zero to a running build, understand the public contracts, and know where the bodies are buried.*

---

## Build instructions

### Prerequisites
- Flutter SDK (project verified on 3.44.x; anything 3.27+ should work — see pitfalls for version-sensitive APIs)
- Android SDK + a Pixel device or emulator
- **Do NOT put the project in a OneDrive/Dropbox/synced folder.** File-sync locks break `build_runner` and Gradle on Windows. Use a plain local path like `C:\dev\neuroflow`. (This cost real debugging time — see pitfalls.)

### First build, in order
```bash
# 1. If starting from the lib/ tree without an android/ shell:
flutter create --platforms=android,ios --org com.neuroflow .

# 2. Dependencies
flutter pub get

# 3. Generate Drift code (REQUIRED — database.g.dart is gitignored)
dart run build_runner build --delete-conflicting-outputs

# 4. Verify
flutter analyze     # expect 0 errors (const-lint infos are fine)

# 5. Run
flutter run
```

**Critical:** step 3 is mandatory and must re-run after ANY change to `database.dart`. Without it you'll see a wall of "TasksCompanion undefined / database.g.dart not generated" errors — that's missing codegen, not broken code.

### Windows-specific
- Keep the project off OneDrive (above).
- If Gradle/`build_runner` hits "Access is denied" deleting build files, a file indexer or AV is scanning `build\`. Add a Defender exclusion for the project folder, or stop the offending process.

---

## Codebase tour (where to start reading)

Read in this order to understand the app:
1. **`lib/domain/task.dart`** — the simplest complete entity. See the pure-model pattern.
2. **`lib/executive/planner.dart`** — the brain. `Executive.evaluate()`, `Plan`, the `PlanAdvisor` seam. This is the conceptual core.
3. **`lib/app/providers.dart`** — the composition root. How every layer wires together. The `TodayController` at the bottom is the key bridge.
4. **`lib/presentation/today_screen.dart`** — how the UI consumes a `Plan`. Biggest file; the focus-timer widgets live here too.
5. **`lib/data/database.dart`** — the schema and the DB method surface.

Everything else is variations on these patterns.

---

## API & Data Contracts

### Repository interfaces (the data-layer public surface)

```dart
abstract class TaskRepository {
  Stream<List<Task>> watchPending();
  Stream<int> watchCompletedTodayCount();
  Future<void> save(Task task);
  Future<void> markComplete(String id);
  Future<void> delete(String id);
}

abstract class HabitRepository {
  Stream<List<Habit>> watchActive();
  Future<void> checkIn(String habitId, {bool completed = true});
  Future<void> uncheckToday(String habitId);
  Future<void> save(Habit habit);
  Future<void> archive(String habitId); // soft-delete (isActive = false)
  Future<void> delete(String habitId);  // hard-delete + check-ins
}

abstract class RoutineRepository {
  Stream<List<Routine>> watchActive();
  Future<List<Routine>> fetchDueNow();   // honors activeDays weekday rule
  Future<void> save(Routine routine);
  Future<void> updateStep(RoutineStep step);
  Future<void> resetRoutine(String routineId);
  Future<void> delete(String routineId);
}

abstract class NoteRepository {
  Stream<List<Note>> watchAll();          // pinned first, then newest
  Future<void> save(Note note);
  Future<void> delete(String id);
}

abstract class MoodRepository {
  Stream<MoodLog?> watchToday();          // Quick Wins signal source
  Stream<List<MoodLog>> watchRecent({int days = 7});
  Future<void> log(MoodLog entry);
}
```

### Executive contract (the planning core)

```dart
enum DayMode { normal, quickWins }

class Plan {
  final DayMode mode;
  final Task? primaryTask;      // the one next-best-action (normal mode)
  final List<Task> quickWins;   // the gentle list (quickWins mode)
  final String reason;
}

class Executive {
  // PURE. Synchronous. No I/O. Same inputs → same Plan.
  Plan evaluate(List<Task> pending, {MoodLevel? mood});
}

abstract class PlanAdvisor {
  // The ONLY AI door. Must never throw — returns plan unchanged on any error.
  Future<Plan> refine(Plan plan, List<Task> allPending);
}
// Implementations: NoOpPlanAdvisor (default), LexiPlanAdvisor (on-device),
// CloudGeminiPlanAdvisor (opt-in, stubbed).
```

### Domain entities (quick reference)
- **Task**: id, title, notes?, `EnergyLevel` {low,medium,high}, `TaskStatus` {pending,completed,skipped}, dueDate?, isQuickWin, estimatedMinutes?
- **Habit**: id, name, frequency, isActive, + streak logic (`isCheckedToday`, `currentStreak`)
- **Routine**: id, name, `RoutineAnchor` {morning,midday,evening,custom}, scheduleHour?, scheduleMinute?, `activeDays`? ("12345"=weekdays, null=daily), steps[]
- **RoutineStep**: id, routineId, position, title, durationMinutes?, isComplete
- **Note**: id, body, pinned, linkedTaskId?, + `firstLine`/`rest` for promote-to-task
- **MoodLog**: id, `MoodLevel` {veryLow,low,neutral,good,great}, loggedAt, + `triggersQuickWins` (≤ low)

### Method channel contract (Lexi bridge)
Channel: `neuroflow/lexi`
- `checkGeminiNanoAvailable()` → bool (stub: false)
- `generateResponse({systemPrompt, userMessage, maxTokens, temperature})` → String? (stub: null)

Dart names are authoritative — Kotlin must match them exactly.

---

## Google OAuth setup (for when Phase 3 sync is built)

Not needed for the current build. When implementing sync:
1. Create a Google Cloud project, enable Calendar API + Tasks API.
2. Configure the OAuth consent screen (will be in "testing" mode → refresh tokens expire every 7 days until verified; fine for personal use).
3. Create an Android OAuth client tied to the app's **SHA-1 fingerprint** (from the signing key).
4. Store credentials in `flutter_secure_storage` — **never in source.**
5. Scopes: minimal — `calendar.readonly` (read-first), `drive.file` (app-created only). No Contacts.

See `CALENDAR-INTEGRATION-SCOPE.md` for the full phased plan.

---

## Testing status
**No test suite currently exists** (see TECH_DEBT TD-05). When building tests, the Executive is the highest-value, easiest target — it's pure and deterministic. Use `AppDatabase.forTesting(NativeDatabase.memory())` for repository tests.

---

## Common debugging pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Wall of "database.g.dart not generated / Companion undefined" | `build_runner` didn't run after schema change | `dart run build_runner build --delete-conflicting-outputs` |
| "Access is denied" during build (Windows) | Project in OneDrive, or AV scanning `build\` | Move off OneDrive; add Defender exclusion |
| Lexi never responds even with SDK | `MainActivity` package ≠ applicationId, channel unregistered | Match package in MainActivity.kt / LexiBridge.kt to build.gradle |
| `NetworkType.not_required` undefined | workmanager floated past 0.5.x | Pin `workmanager: 0.5.2` (no caret), or update to new enum casing |
| Seed changes don't appear | Seeds run first-launch only | Clear app data, relaunch |
| `withOpacity` deprecation warnings | Flutter 3.27+ renamed to `withValues(alpha:)` | Use `.withValues(alpha: x)`; blanket-swap if on older Flutter |
| `CardTheme` type error | Newer Flutter expects `CardThemeData` | Use `CardThemeData` in ThemeData.cardTheme |
| Task completion doesn't refresh UI | Misunderstanding — it's stream-driven | It works; `pendingTasksProvider` re-emits on Drift write |

---

## The one rule that matters most
Before adding anything, ask: **does this reduce the user's decisions, or create new ones?** If it adds management overhead without reducing cognitive load, it doesn't belong. This app is an executive-function prosthetic — every feature must carry load *off* the user, never onto them.
