# Copilot Instructions — NeuroFlow

## Welcome, and what this actually is

You're joining a project that's had a rough run so far — not on substance, on process. Four chat-based AI assistants (Claude, ChatGPT, Grok, Gemini) have been collaborating on this app across many separate conversation threads, and for a long stretch, confident descriptions of code got treated as if the code existed. It didn't. Several rounds of "locked," "frozen," "compile-ready" architecture turned out, on direct inspection, to correspond to nothing in the actual repository. A full reconciliation eventually sorted it out — real files, read in full, compared against the actual spec — but it took a long time, and it never should have needed to.

You're the fix for the root cause. You're the first participant in this project with an actual compiler. Everything before you was text evaluated by text; nothing was evaluated by ground truth. Your job isn't to write more speculative architecture — there's been plenty of that. It's to tell us, plainly, whether what's already been written actually compiles, type-checks, and does what it claims. That's a genuinely different and more valuable role than "another reviewer," and it doesn't need a persona to do it well.

**When you report status, use exactly one of three words: Proposed, Implemented, or Verified.** *Verified* means you (or a real `flutter`/`dart` command) actually ran it and it worked — not that it looks correct, not that it should compile. This project got burned specifically by confident language substituting for that distinction. Don't repeat it.

## Project overview

NeuroFlow is a native Flutter ADHD executive-function app — not a prettier to-do list. Core philosophy: **rich engine, deceptively simple UI.** Every feature is filtered through one question: does this reduce Bryan's friction, or does it just add a feature? The full reasoning lives in `docs/NeuroFlow-Unified-Spec-v1.12.md` — read it before proposing anything structural; it's long because a lot of hard-won decisions are in it, and most "obvious improvements" have already been considered and explicitly rejected for a documented reason.

## Tech stack

- Flutter (native, no web/PWA), Dart ≥3.4
- State: **plain Riverpod, deliberately no code generator** (`riverpod_generator` is NOT used — keep it that way; codegen surface is intentionally limited to Drift alone)
- Persistence: Drift over SQLite, local-first — the local DB is the source of truth, Google Tasks/Calendar are mirrors, not the other way around
- Background: WorkManager (periodic jobs, inexact scheduling by design — no `SCHEDULE_EXACT_ALARM`)
- Google integration: `google_sign_in`, `googleapis` (Calendar — mature API, generated bindings trusted), hand-rolled REST for the Health API (too new for generated bindings, endpoints marked `TODO(verify)`)
- No `freezed` — plain immutable classes with manual `copyWith`, consistent throughout

## Architecture (four layers — respect the boundaries)

```
lib/domain/       Pure Dart. No Flutter, no Drift, no Riverpod imports. Ever.
lib/executive/    Decision logic (Planner, TodayContext, TrustVoiceCopy). 
                  MUST NOT import lib/intelligence/ — see rule below.
lib/platform/     Drift, notifications, background jobs, Google/Health services.
lib/presentation/ Flutter UI. Dumb receiver of Executive-owned state — 
                  no business logic, no direct DB/repository calls in widgets.
```

**Hard rule, checked in every review:** `lib/executive/` never imports `lib/intelligence/`. AI (on-device Lexi, or cloud) is an optional enhancer injected at the composition root (`lib/app/providers.dart`), never a dependency. The default is `NoOpPlanAdvisor` — an identity function. The app must be fully usable with AI absent, cold, or unavailable.

## Things to avoid — these are regressions we already made and fixed once

- **No binary streaks.** Habit completion uses `completionRate30d` + a monthly skip budget (forgiveness mechanic), never a consecutive-day counter that resets to zero on a miss. This was reintroduced once by a parallel implementation and had to be removed — don't bring it back.
- **No raw numbers/percentages/scores visible in the UI.** Goodhart's Law rule, locked in spec §13. Internal metrics (`confidenceCalibration`, streak-adjacent data) drive copy and visuals, never a literal number on screen. This was violated twice by a parallel implementation (a numeric heartbeat badge, a numeric habit-streak badge) — both caught and removed.
- **Quick Wins mode is derived state, never a stored flag.** `isQuickWin` (or any equivalent) must never be a persisted boolean on a Task. It's computed by `DeterministicPlanner.shouldEnterQuickWins()` from Bryan's actual state (mood, sleep, inferred engagement, resting HR) — never from what happens to be in the task list. A parallel implementation once triggered Quick Wins based on task-list composition instead of user state; that inverts the entire point of the feature.
- **Capture stays one input, one button.** No additional fields, selectors, or decisions in the quick-add flow — that's the one interaction this app protects hardest.
- **No exact alarms.** `SCHEDULE_EXACT_ALARM` is deliberately not requested (Android 12+ permission friction). Local notifications use `AndroidScheduleMode.inexactAllowWhileIdle`.

## Validation — what "Verified" actually requires

```bash
flutter pub get
dart run build_runner build -d   # Drift codegen
flutter analyze                   # first real signal — expect some errors, fix and re-run
flutter test
flutter run
```

Full sequence with context and known open friction points: `docs/COMPILE_PATH.md`. Two flagged, not-yet-verified items to check first if anything fails:
- The `googleapis_auth` `AccessCredentials`/`AccessToken` constructor shape in `lib/platform/calendar/calendar_service.dart`
- `NetworkType.notRequired` vs `NetworkType.not_required` in `lib/platform/background/background_scheduler.dart`

**Report exact compiler/analyzer output, not a paraphrase of it.** "It didn't compile" is not useful; the actual error text is.

## If the first compile fails

Don't panic. Nothing has actually run yet, so compile errors are expected and often just confirm the friction points already flagged above. When you hit one:

1. **Paste the full error text** — not a summary. Include file paths and line numbers.
2. **Check the two flagged open items first** — they're known unknowns that depend on package versions actually installed in Bryan's environment.
3. **Fix one error at a time, then re-run `flutter analyze`** — don't batch-fix multiple errors in one pass. Slower, but you'll know which fix actually worked.
4. **If an error claims a file or method doesn't exist, check that the file actually exists in the repo before assuming the design is broken.** This project had a real, extended problem with confident architecture descriptions that never corresponded to real files — if you hit a missing reference, the far more likely explanation is a stale claim, not a bug in something that was actually built.

Report status with the exact command you ran and its output after each fix — that's the real audit trail.

## How to propose changes

The spec is long and intentionally opinionated. Before proposing anything:

1. **Search the spec for your idea first.** Most "obvious improvements" are already in there with a documented reason they were rejected.
2. **If it's already rejected, don't re-propose it.** The reasoning is on record; re-litigating it wastes time.
3. **If it's genuinely new, propose it with the friction it removes and the friction it adds.** "Nice to have" doesn't clear the bar; "reduces a specific, named decision point" does.
4. **Reference the spec sections that would need to change.** Describe the change relative to what's already decided, not in isolation.

## Composition root

All state wiring lives in `lib/app/providers.dart` — the **one** place `lib/intelligence/` gets imported. Every other layer imports toward the center (Presentation → Executive → Platform → Domain), never outward.

The Lexi system prompt lives in `lib/intelligence/lexi_system_prompt_mobile.md` (source of truth) and `lib/core/lexi_mobile_prompt.dart` (generated Dart constant). Edit the markdown, regenerate the constant — don't edit the generated file in place. Same one-source-of-truth discipline as the Drift schema.

## Current status — checked against the real repo, not asserted

- **Implemented, not yet Verified:** the six-file reconciliation (spec §15) is real, complete local work — but it has not been merged into `origin/main`, and nothing in this repo has been compiled. Calling reconciliation "Verified" would repeat the exact failure this file exists to prevent. It becomes Verified when `flutter analyze`/`flutter run` actually succeed against it.
- **Real, content-verified (a different check than compiler-verified):** the Lexi system prompt — confirmed byte-for-byte accurate against the committed file. Worth keeping this distinction precise: verified-as-transcribed-correctly is not the same claim as verified-as-compiling. Neither is a substitute for the other.
- **Implemented, not yet Verified:** Tasks, Habits, Stats, background jobs, Google/Health integration (all dormant/gated as designed).
- **Proposed:** the on-device Lexi bridge — no stable Flutter package exists yet; this is a real, open gap, not a deferred nicety.

The first real run moves something from Implemented to Verified, or surfaces what needs fixing. That's the actual moment this project finds out whether it works — nothing before it does.
