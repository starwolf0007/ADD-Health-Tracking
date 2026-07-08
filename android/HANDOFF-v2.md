# NeuroFlow v2 — Baseline Handoff (for Claude Code / Copilot)

**From:** architecture + wiring pass (this session)
**To:** the compiler-having agent
**Status:** feature-complete v2 baseline, internally consistent, **never compiled** (no Flutter SDK in the authoring environment). Your job: run the compile loop, fix what the analyzer surfaces, get it on the Pixel.

---

## TL;DR — what this is

The bones of NeuroFlow v2: a local-first ADHD hub with four tabs (Today · Notes · Routines · Reflect), a focus timer built for time-blindness, and a mood check-in that reshapes the day. Every layer is wired end to end. The one thing standing between this tree and a running app is code generation + a real `flutter analyze` pass, which needs your toolchain.

## Run this first (exact sequence)

```bash
# 1. Generate the Android/iOS shell around this lib/ (the tree has no android/ gradle yet
#    beyond the two Kotlin files below — flutter create fills the rest in, non-destructively).
flutter create --platforms=android,ios --org com.neuroflow .

# 2. Deps
flutter pub get

# 3. Drift codegen — creates lib/data/database.g.dart (REQUIRED; nothing compiles without it)
dart run build_runner build --delete-conflicting-outputs

# 4. Analyze
flutter analyze
```

**Expected after step 3:** `database.g.dart` appears. Until it does, every import of `database.dart` shows errors — that's normal pre-codegen, not a real failure. Don't chase those before running build_runner.

## What to place carefully

- `android/app/src/main/kotlin/com/neuroflow/MainActivity.kt` and `.../lexi/LexiBridge.kt` are included. After `flutter create`, **confirm the generated `applicationId` in `android/app/build.gradle` matches `com.neuroflow`** — if it differs, update the `package` line in both Kotlin files to match, or the plugin won't register.
- If `flutter create` overwrites `MainActivity`, restore the included one (it registers `LexiBridge`).

## What's wired (verified by cross-file audit this session)

- **Composition root** (`lib/app/providers.dart`): every repo + provider, including new `noteRepositoryProvider`, `moodRepositoryProvider`, `activeNotesProvider`, `todayMoodProvider`, `recentMoodsProvider`, `activeRoutinesProvider`.
- **The §6 Quick Wins trigger is LIVE**: `TodayController.build()` reads today's mood and passes it into `Executive.evaluate(pending, mood:)`. A check-in at Low or below reshapes Today into ≤3 gentle wins. Executive stays pure — mood is passed in as data, so determinism holds.
- **Focus timer** (`lib/app/focus_timer.dart` + Today card): target chips (5/15/30/60, seeded with the task's own estimate), live count-up in mono numerals, thin progress line, haptic milestones at halfway / T-2 / target-crossed, kind amber overtime ("3 over — still yours").
- **Four-tab shell** (`app_shell.dart`), Notes/Reflect/Routines screens, mood check-in, week strip, capture estimate chips.
- **Unified 7-table schema** (`lib/data/database.dart`): Tasks, Habits, HabitCheckIns, Routines, RoutineSteps, Notes, MoodLogs. Every `_db.*` call in the repo impls was checked against a defined method — all resolve.
- **Truncation repaired**: `notification_service.dart` and `routine_repository_impl.dart` were both cut mid-file in the source repo; both completed and brace-balanced. Full-tree scan shows no remaining truncated files.

## Known-unknowns for the compiler (things I couldn't verify without a toolchain)

1. **`withValues(alpha:)`** — used consistently across `today_screen.dart` and `reflect_screen.dart`. This is the Flutter 3.27+ replacement for deprecated `withOpacity`. If the installed Flutter is older than 3.27, do a blanket swap to `.withOpacity(x)`: `grep -rln withValues lib/` then replace `.withValues(alpha: X)` → `.withOpacity(X)`.
2. **Riverpod generator** — the tree uses plain providers (hand-written, no `@riverpod` codegen), so `riverpod_generator` in dev_deps is unused-but-harmless. `build_runner` still needs to run for **Drift**. If you prefer, you can remove `riverpod_generator`/`riverpod_annotation` from pubspec — nothing imports them.
3. **`NavigationBarThemeData` / `WidgetStateProperty`** — Material 3 names, correct for Flutter 3.16+. Older SDK → `MaterialStateProperty`.
4. **Focus timer background firing** — the halfway/T-2/target haptics fire only while the app is foregrounded. Background notifications at those milestones need a lifecycle hook into `NotificationService` — deliberately deferred (marked `TODO(device)` in `focus_timer.dart`), because it needs on-device testing.

## Deliberately deferred (NOT bugs — don't "fix" these)

- **No Google sync yet.** Drift is the sole source of truth. Sync (Tasks/Calendar mirror, Health Connect mood I/O) is the next phase — see the mood-sync research doc. The Cloud advisor and OAuth are stubbed.
- **Lexi advisor NoOps** until the Gemini Nano SDK is wired to `LexiBridge.kt`. The seam is correct; the native model call is a TODO with comment anchors.
- **§2.8 change:** mood was originally on-device-only. The project owner has since decided mood SHOULD sync outward (Health/Fit, Lexi, Home) for a synergetic Google-ecosystem experience. **The current `MoodLogs` table still has no sync columns** — that's the *starting* state, correct for this baseline. The sync layer will add an explicit, opt-in mirror path in the next phase. Do not add mood sync in this pass.

## First-run behavior

On first launch: seeds insert two routines (morning launch, evening wind-down) and three habits, then `resetRoutinesIfNewDay` runs. You should land on the Today tab with a next-best-action card. Capture a task (+ button), set an estimate, watch the focus timer run. Log a Low mood on Reflect → Today flips to Quick Wins.

## If you hit a wall

The architecture is four-layer (Domain / Data / Executive / Presentation) with the AI seam isolated in `lib/intelligence/`. If something doesn't resolve, the contract is: Presentation reads providers only; Executive is pure and imports domain only; the PlanAdvisor seam is the sole AI door. Anything violating that is the bug.
