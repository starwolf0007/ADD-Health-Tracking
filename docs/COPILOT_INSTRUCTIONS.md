# Copilot Instructions — NeuroFlow

Written for Copilot and any other IDE-resident agent with a real compiler. Most
of it applies to any AI collaborator on this repo.

## Why this file exists

For a long stretch, this project was built by four chat-based AI assistants
across separate conversation threads, and confident descriptions of code got
treated as if the code existed. It didn't. Several rounds of "locked," "frozen,"
"compile-ready" architecture turned out, on direct inspection, to correspond to
nothing in the repository. A full reconciliation sorted it out — real files, read
in full, compared against the actual spec — but it took far longer than it should
have.

That specific failure is now fixed. The project compiles, `flutter test` passes,
and Android CI runs `pub get` → `build_runner` → `flutter test` on every push and
PR to `main`. Ground truth is cheap to obtain now, which changes your job: not
"be the first participant with a compiler," but **keep the gap between what the
docs claim and what the code does from reopening.**

The discipline that came out of that period still holds. **Report status using
exactly one of three words: Proposed, Implemented, or Verified.** *Verified*
means a real `flutter`/`dart` command ran and you are quoting its actual output —
not that the code looks correct, not that it should compile. If you could not run
the command, say «Not executed.»

Related: `AGENTS.md` (collaboration contract), `docs/ARCHITECTURE.md` (layer
model and ADR precedence), `docs/COMPILE_PATH.md` (build sequence, what CI does
and does not cover).

## Project overview

NeuroFlow is a native Flutter ADHD executive-function app — not a prettier to-do
list. Core philosophy: **rich engine, deceptively simple UI.** Every feature is
filtered through one question: does this reduce Bryan's friction, or does it just
add a feature?

Full reasoning: `docs/NeuroFlow-Unified-Spec-v1.4.md`. Read it before proposing
anything structural — it is long because a lot of hard-won decisions are in it,
and most "obvious improvements" have already been considered and explicitly
rejected for a documented reason.

## Tech stack

- Flutter (native Android; no web/PWA), Dart ≥ 3.4. CI pins Flutter 3.44.6, Java 17.
- State: **plain Riverpod, deliberately no code generator.** `riverpod_generator`
  sits in `dev_dependencies` but is unused for app state — keep it that way. The
  only `part` directive in `lib/` is Drift's. **Codegen surface is Drift alone.**
- Persistence: Drift over SQLite at `lib/data/database.dart`, schema v7,
  local-first — the local DB is the source of truth; cloud services are mirrors,
  never the reverse.
- Background: WorkManager, periodic and inexact by design — no `SCHEDULE_EXACT_ALARM`.
- Google: `google_sign_in`, `googleapis`. Sign-in and the sync-queue plumbing
  exist; Calendar integration is scoped but unbuilt (see
  `CALENDAR-INTEGRATION-SCOPE.md`).
- Health: **Health Connect over a native Kotlin MethodChannel**, not a REST API.
  Steps only, read-only, governed by ADR-007.
- No `freezed` — plain immutable classes with manual `copyWith`, or Dart 3 sealed
  classes.

## Architecture — respect the boundaries

```
lib/domain/       Pure Dart entities + repository interfaces.
                  No Flutter, Drift, or Riverpod imports. Ever.
lib/executive/    Decision logic. Pure Dart, domain only.
                  MUST NOT import lib/intelligence/ — see below.
lib/data/         Repository implementations + the Drift database.
lib/health/       Phase-1 medical-tier write guard (ADR-007).
lib/platform/     Notifications, background jobs, alarms, sync, wear,
                  Google, Health Connect, Hevy.
lib/intelligence/ Optional Lexi/cloud advisors.
lib/presentation/ Flutter UI. Passive receiver of executive-owned state —
                  no business logic, no direct DB/repository calls in widgets.
lib/app/          Composition root. The one place intelligence is wired in.
lib/screens/prototypes/  Locked, device-tested interaction reference.
                  Excluded from analysis. Do not "clean up".
```

**Hard rule, checked in every review:** `lib/executive/` never imports
`lib/intelligence/`. AI is an optional enhancer injected at the composition root
(`lib/app/providers.dart`), never a dependency. The default is `NoOpPlanAdvisor`,
an identity function. The app must be fully usable with AI absent, cold, or
unavailable.

Full layer contract and the ADR precedence chain: `docs/ARCHITECTURE.md`.

## Things to avoid — regressions we already made once

These are owner doctrine. Three of them are **currently contradicted by shipped
code**; those are flagged inline. Do not resolve a flagged conflict as a side
effect of unrelated work — neither by changing the code nor by quietly softening
the rule. Raise it and get a decision.

- **No binary streaks.** Habit progress should come from a completion rate over a
  window plus a monthly skip budget (forgiveness mechanic), never a
  consecutive-day counter that resets to zero on a miss.
  > ⚠️ **Open conflict.** `Habit.currentStreak` and `Habit.longestStreak` in
  > `lib/domain/habit.dart` are exactly that counter — `currentStreak` breaks on
  > the first incomplete check-in. No `completionRate30d` or skip budget exists
  > anywhere in `lib/`. The behavior is covered by `test/unit/habit_test.dart`,
  > so it is deliberate, not drift.

- **No raw numbers, percentages, or scores visible in the UI** (Goodhart's Law,
  spec §13). Internal metrics drive copy and visuals, never a literal number on
  screen.
  > ⚠️ **Open conflict, currently dormant.** `_StreakBadge` in
  > `lib/presentation/habits_widget.dart` renders the streak count as literal
  > text. Nothing renders today — `HabitsWidget` is not instantiated by any
  > screen — but the violation lands the moment it is wired in.

- **Quick Wins mode is derived state, never a stored flag.** `isQuickWin` or any
  equivalent must never be a persisted boolean on a Task. It should be computed
  from Bryan's actual state (mood, sleep, inferred engagement, resting HR), never
  from what happens to be in the task list — deciding from list composition
  inverts the entire point of the feature.
  > ⚠️ **Open conflict, live.** `Executive.evaluate()` in
  > `lib/executive/planner.dart` enters Quick Wins when every pending task is
  > low-energy and there are three or fewer — task-list composition, precisely
  > the inversion this rule names. It is live: `lib/app/providers.dart` feeds its
  > output straight into `TodayState.mode`, and `test/unit/executive_test.dart`
  > locks the behavior in. The `DeterministicPlanner.shouldEnterQuickWins()` this
  > rule used to cite does not exist in `lib/`; the user-state inputs it names
  > are not plumbed. Correctly derived state, wrong derivation.

- **Capture stays one input, one button.** No additional fields, selectors, or
  decisions in the quick-add flow — that is the one interaction this app protects
  hardest.

- **No exact alarms.** `SCHEDULE_EXACT_ALARM` is deliberately not requested
  (Android 12+ permission friction). Local notifications use
  `AndroidScheduleMode.inexactAllowWhileIdle`. The manifest is clean on this.
  > Worth knowing: `android/app/src/main/kotlin/dev/neuroflow/ExactAlarmScheduler.kt`
  > does call `setExactAndAllowWhileIdle`, but it is one of the unregistered
  > bridges below — nothing invokes it — and it gates on `canScheduleExactAlarms()`
  > with an inexact fallback. Not a live violation; do not wire it up without a
  > decision on the rule.

Today-screen interaction behaviors are separately locked by
`docs/today_screen_interaction_contract.md`.

## Validation — what "Verified" actually requires

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs -d   # Drift codegen
flutter analyze
flutter test
flutter run -d <device-id>
```

`lib/data/database.g.dart` is gitignored, so step 2 is mandatory on a fresh
clone. Note that **`flutter analyze` is not a CI step** — analyzer regressions
can merge, so run it locally before pushing.

**Report exact compiler/analyzer output, not a paraphrase.** "It didn't compile"
is not useful; the actual error text is. Fix one error at a time and re-run
rather than batch-guessing several fixes, so you know which change worked.

If an error claims a file or method does not exist, check whether the file is
actually in the repo before assuming the design is broken. Given this project's
history, a stale claim in a document is a likelier explanation than a bug in
something that was genuinely built.

Full detail, plus what does not need to work yet: `docs/COMPILE_PATH.md`.

## How to propose changes

1. **Search the spec for your idea first.** Most "obvious improvements" are
   already in there with a documented reason they were rejected.
2. **If it is already rejected, do not re-propose it.** The reasoning is on
   record.
3. **If it is genuinely new, propose it with the friction it removes and the
   friction it adds.** "Nice to have" does not clear the bar; "removes a
   specific, named decision point" does.
4. **Reference the spec sections that would need to change.**

An ADR outranks this file. A feature request does not implicitly authorize
overriding one — surface the conflict instead.

## Composition root

All state wiring lives in `lib/app/providers.dart` — the one place
`lib/intelligence/` is imported. Every other layer imports toward the center.

The Lexi system prompt's source of truth is
`lib/intelligence/lexi_system_prompt_mobile.md`; the Dart constant mirroring it
is `lib/intelligence/lexi_mobile_prompt.dart`, whose header says not to edit it
directly. Edit the markdown, then regenerate the constant — the same
one-source-of-truth discipline as the Drift schema. (That file's own header
comment still cites its former `lib/core/` path; the directory no longer exists.)

## Current status

Checked against the repo, not asserted:

- **Verified:** the project builds and `flutter test` passes. CI has run the full
  sequence on every push and PR to `main`, green through the current head.
- **Implemented:** tasks, habits, routines, notes/mood, scheduling rules, the
  Hevy import path, the sync queue, and Google sign-in. Google Tasks/Calendar
  sync remains dormant pending OAuth activation, by design.
- **Implemented, partially:** Health Connect — permission declaration,
  availability mapping, and the permission lifecycle exist. Paged reads,
  transport mapping, persistence, change tokens, and background sync are accepted
  but unbuilt (ADR-007).
- **Proposed:** the on-device Lexi bridge. No stable Flutter package for
  on-device inference exists yet; `MissingPluginException` on `neuroflow/lexi` is
  expected, and the app falls back to `NoOpPlanAdvisor`. Top build risk.
- **Unregistered seams:** the `dev.neuroflow` alarm and wear Kotlin bridges are
  not added in `MainActivity`, and `wear/` is not in
  `android/settings.gradle.kts`. The `neuroflow/alarms` and `neuroflow/wear`
  channels have no live native handler.
- **Open doctrine conflicts:** the three flagged above. Unresolved, owner
  decision required.
