# NeuroFlow — Project Rules

NeuroFlow is a native Flutter (Android-first) ADHD/executive-function companion.
Pub package name: `neuroflow`. Repo: `starwolf0007/ADD-Health-Tracking`.

Guiding philosophy: **rich engine, deceptively simple UI.** Every feature is
filtered through one question — does this remove a decision point for the user,
or does it just add a feature?

## Where authority lives

```
Explicit owner authorization for the current task
  → docs/adr/            Architecture Decision Records (binding)
  → docs/ARCHITECTURE.md Living architecture doc
  → AGENTS.md            AI collaboration contract (read-only default, verification discipline)
  → this file            File placement, commands, conventions
  → agent defaults
```

A feature request does **not** implicitly authorize overriding an ADR or an
architectural invariant. If a request conflicts with one: stop, name the
conflict, propose the smallest repo-consistent alternative.

Two documents govern how you work, not just what you build — read them before a
first substantial change:

- `AGENTS.md` — treat the repo as read-only unless the request authorizes edits;
  never report unverified results; tested tree must equal committed tree.
- `docs/ARCHITECTURE.md` — layer model, dependency directions, controller style.

Product source of truth: `docs/NeuroFlow-Unified-Spec-v1.4.md`.
Behavioral regressions already made and fixed once: `docs/COPILOT_INSTRUCTIONS.md`
("Things to avoid") — read that list before touching Today/Habits/Capture.

## Tech stack

- Flutter ≥ 3.22 / Dart SDK `>=3.4.0 <4.0.0`, sound null safety. CI pins Flutter 3.44.6, Java 17.
- **State: plain Riverpod** (`flutter_riverpod` ^3). `riverpod_annotation` /
  `riverpod_generator` are in `pubspec.yaml` but deliberately unused for app
  state — **codegen surface is Drift only**. Do not introduce `@riverpod`.
- **Persistence: Drift over SQLite**, local-first. The local DB is the source of
  truth; Google Tasks/Calendar and Hevy are mirrors, never the reverse.
- **No `freezed`.** Plain immutable classes with hand-written `copyWith`, or
  Dart 3 sealed classes. Keep it that way.
- Background: `workmanager` (inexact by design). Notifications:
  `flutter_local_notifications` with `AndroidScheduleMode.inexactAllowWhileIdle`.
- Google: `google_sign_in` ^7, `googleapis` ^16. Secrets: `flutter_secure_storage`.
- Android: `minSdk 31`, `targetSdk 35`, namespace `com.neuroflow`, Health Connect
  `connect-client:1.1.0`.
- UI is Material 3, **dark-only by design** (spec §13) — see `lib/presentation/theme.dart`.

## Build & development commands

`lib/data/database.g.dart` is gitignored and **must be generated before anything
compiles**:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs -d   # Drift codegen
flutter analyze
flutter test
flutter run -d <device-id>          # or: flutter build apk --release
```

- Re-run `build_runner` after any change to `lib/data/database.dart`.
- `scripts/run_green_gate.ps1` / `.bat` run the owner's local Windows gate
  (pub get → build_runner → `flutter build apk --debug`). They are hardcoded to
  `C:\Dev` — they are the owner's local tooling, not portable CI.
- `scripts/diagnose.bat` is the noisier variant that also runs `flutter analyze`.

**The cloud/CI container for agent sessions has no `flutter` or `dart` on PATH.**
If you cannot run a command, report «Not executed.» — never infer analyzer,
test, or build results. This rule exists because this project was previously
damaged by confident claims about code that had never been compiled.

Status vocabulary, used exactly: **Proposed** / **Implemented** / **Verified**.
*Verified* means a real command ran and its actual output is quoted.

## Architecture — layers and hard rules

```
lib/domain/        Pure Dart entities + repository interfaces.
                   No Flutter, Drift, Riverpod, or Google imports. Ever.
lib/executive/     Decision logic — planner, day resolver, timeline logic.
                   Pure Dart, depends on domain only.
                   MUST NEVER import lib/intelligence/.
lib/data/          Repository implementations + the Drift database.
                   Depends on domain only.
lib/health/        Health-evidence write guards enforcing the Phase-1
                   medical-tier boundary (see ADR-007).
lib/platform/      OS/device/cloud integration — notifications, background work,
                   alarms, wear, sync, settings, Google, Health Connect, Hevy.
lib/intelligence/  Lexi on-device bridge + optional cloud adapter.
                   Implements executive/planner.dart's PlanAdvisor.
lib/presentation/  Flutter UI. Screens at top level, shared widgets under
                   presentation/widgets/. Passive — no business rules,
                   no direct repository or Drift access from widgets.
lib/app/           Riverpod composition root — providers.dart, bootstrap.dart,
                   database_providers.dart, hevy_providers.dart, achievements.dart.
                   The ONLY place intelligence is wired in.
lib/screens/prototypes/  Approved, device-tested interaction reference.
                   Locked; excluded from analysis. Do not "clean up".
```

Permitted dependency directions: `Presentation → Executive → Domain`, with
`App → Platform → Domain` and intelligence injected only at `lib/app/`.

Invariants that get checked in every review:

- **Executive never imports intelligence.** AI is an optional enhancer. The
  default `PlanAdvisor` is `NoOpPlanAdvisor` (identity). The app must be fully
  usable with AI absent, cold, or failing. (ADR-001, ADR-006)
- **Controllers expose intent methods only** (`acceptDay`, `startReview`,
  `notNow`, `undo`). No public `copyWith` on state, no public lifecycle setters
  like `loadProposal`/`setLoading`. Seed through injection, not setters. (ADR-004)
- **Prefer sealed classes** so illegal states are unrepresentable; transitions
  pattern-match first and are safe no-ops in an invalid context. (ADR-003)
- **Widget-tree changes require explicit authorization.** (ADR-005)
- Prefer dependency injection over global state; keep public APIs minimal.

New code goes in the layer it belongs to, not the layer that is most convenient.

### Product rules that look like bugs if you don't know them

These were each implemented wrong once and fixed; don't reintroduce them:

- **No binary streaks.** Habits use `completionRate30d` plus a monthly skip
  budget, never a consecutive-day counter that resets to zero.
- **No raw numbers, percentages, or scores in the UI** (Goodhart's Law, spec §13).
  Internal metrics drive copy and visuals, never a literal number on screen.
- **Quick Wins is derived state, never a persisted flag** on a Task.
- **Capture stays one input, one button.** No extra fields in the quick-add flow.
- **No exact alarms.** `SCHEDULE_EXACT_ALARM` is deliberately not requested.
- Today-screen interaction behaviors are locked by
  `docs/today_screen_interaction_contract.md` — amending them is a reviewed
  proposal, not a side effect of wiring real data.

## Data & health boundaries

- Drift schema is at `lib/data/database.dart`, currently **schemaVersion 7**.
  Migrations are additive `onUpgrade` branches; **every schema bump needs a
  migration test** (see `test/unit/health_v6_to_v7_migration_test.dart`).
- Health enums are persisted via `intEnum<T>()` — **reordering an existing enum
  value is a schema change.** Append only (`lib/domain/health/health_enums.dart`).
- Health Connect is a sensor bus, not a domain model (ADR-007). Kotlin emits
  plain MethodChannel primitives; Dart owns parsing, normalization, and
  deterministic IDs via `generateHealthEvidenceId()`. Ingestion never merges,
  sums, deduplicates, or picks a preferred provider — one upstream record
  produces exactly one transaction. Current declared scope is **Steps only**.
- Every health transaction must pass `HealthWriteGuard.requirePhase1Transaction()`
  before persistence. Medical-tier evidence is rejected, not stored.
- Health exceptions carry reason codes and safe identifiers only — never raw
  values, notes, measurements, or external IDs.
- Secrets (API keys, tokens) never reach the UI or exception text — see the Hevy
  screen tests for the expected assertions.

## Native / Android

```
android/app/src/main/kotlin/com/neuroflow/    MainActivity, healthconnect/, lexi/  (registered)
android/app/src/main/kotlin/dev/neuroflow/    AlarmBridge, ExactAlarmScheduler, WearBridge
wear/                                         Wear OS tile/complication sources
```

- `MainActivity` registers `LexiBridge` and `HealthConnectBridge` only. The
  `dev.neuroflow` bridges are unregistered seams — the Dart `neuroflow/alarms`
  and `neuroflow/wear` channels have no live native handler today. Treat a
  `MissingPluginException` there as the known gap, not a regression.
- `wear/` is not included in `android/settings.gradle.kts`; it is source, not a
  built module.
- MethodChannels: `neuroflow/lexi`, `neuroflow/health_connect`,
  `neuroflow/alarms`, `neuroflow/wear`.
- `google-services.json` is intentionally untracked; the Gradle build skips
  Google Services processing when it is absent, and CI only builds the release
  APK when the `GOOGLE_SERVICES_JSON` secret is present.

## File placement

### docs/

```
docs/                      Living specs and references (spec, build notes, design system,
                           connected services, compile path, integrations)
docs/adr/                  Architecture Decision Records — binding; update the index README
docs/reference/            External reference audits; architecture/ vs ux/ must not be mixed
docs/google/               Google integration architecture, setup, auth
docs/product/              Product/core-principles notes
docs/review/               Validation prompts for review passes
docs/archive/              Point-in-time handoffs, session memos, status snapshots — history, not guidance
```

Root-level `.md` files are limited to `README.md`, `CLAUDE.md`, and `AGENTS.md`.
Anything else — handoff note, design memo, status snapshot — goes in `docs/` or
`docs/archive/`. **This is enforced by CI** (`.github/workflows/repo-hygiene.yml`).

New ADR: follow the template in `docs/adr/README.md` (Status / Context /
Decision / Alternatives Considered / Consequences / Related Documents) and add a
row to the index table.
New external reference: copy `docs/reference/template.md` and add a row to
`docs/reference/reference-matrix.md`.

### scripts/

All `.bat` and `.ps1` helpers live in `scripts/`, never the repo root.

### test/

```
test/unit/                    Domain, executive, data, and service logic — one file per concern
test/domain/health/           Health domain contract tests
test/platform/health_connect/ MethodChannel transport mapping tests
test/platform/hevy/           Hevy API client tests
test/presentation/            Widget tests that need their own directory
test/presentation/goldens/    Golden PNGs (matchesGoldenFile)
test/*.dart                   Flat widget/smoke tests (widget_test.dart, today_screen_test.dart, …)
```

Conventions: Drift tests use `AppDatabase.forTesting(NativeDatabase.memory())`;
Riverpod is exercised through `ProviderContainer` with overrides; widgets are
driven with `Key`-based finders and fakes injected via provider overrides.

**Tests are production assets** (AGENTS.md): never delete, shorten, or comment
out a test for convenience. Compare test counts before and after a change and
explain any reduction.

## CI

- `.github/workflows/android-ci.yml` — push/PR to `main`: pub get → build_runner
  → `flutter test`; release APK on push when the Firebase secret exists.
- `.github/workflows/repo-hygiene.yml` — fails on stray root `.md`, committed
  `.bundle`/`green_gate_log.txt`, or a duplicate project tree under `android/`.
- `.github/workflows/stale-branch-report.yml` — weekly stale-branch issue;
  a PR can carry the `no-stale` label to opt out.

## Working conventions

- Analyzer rules beyond `flutter_lints`: `always_use_package_imports` (use
  `package:neuroflow/...`, not relative), `prefer_const_constructors`,
  `avoid_print`, `avoid_void_async`, `unawaited_futures`.
- Handle async calls with try/catch and surface user-friendly error states;
  safe no-op behavior is preferred over throwing where appropriate.
- Layouts must adapt across Android screen sizes.
- Read a file completely before editing it; make the smallest correct change;
  never replace a working implementation with an abbreviated one, and never
  commit placeholders, `TODO`-as-substitute-for-work, or "... unchanged ...".
- Modify only what the task requires. Report discovered improvements separately
  instead of implementing them.
- Commit style in this repo is mixed: Conventional Commits
  (`fix(health): …`, `docs: …`, `chore: …`) and plain imperative subjects
  (`Add Health Connect availability model`). Either is acceptable; one focused
  change per commit is the real convention.
- The Lexi system prompt's source of truth is
  `lib/intelligence/lexi_system_prompt_mobile.md`; `lexi_mobile_prompt.dart`
  mirrors it. Edit the markdown, then update the Dart constant — same
  one-source-of-truth discipline as the Drift schema.
