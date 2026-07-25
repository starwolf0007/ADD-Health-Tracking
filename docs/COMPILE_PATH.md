# NeuroFlow — Build & Verification Path

**Status of the question this document was written to answer: settled.**
The project compiles, and `flutter test` passes. Android CI has run the full
`pub get` → `build_runner` → `flutter test` sequence on every push and PR to
`main`, and `main` has been green through the current head.

This file used to be "Path to First Compile," written when nothing in the repo
had ever been built and the native scaffolds did not exist. That milestone
passed. What remains useful — and what this file is now — is the exact sequence
to get a working tree building, what CI already guarantees, and the reporting
discipline that got the project out of its earlier confident-but-uncompiled
state. The history is preserved at the bottom rather than deleted.

---

## The build sequence

Run from the repo root. Step 2 is not optional: `lib/data/database.g.dart` is
gitignored, so a fresh clone does not compile until Drift codegen has run.

```bash
flutter pub get

dart run build_runner build --delete-conflicting-outputs -d   # generates lib/data/database.g.dart

flutter analyze
flutter test

flutter run -d <device-id>          # or: flutter build apk --release
```

Re-run `build_runner` after any edit to `lib/data/database.dart`.

**Toolchain.** `pubspec.yaml` requires Dart `>=3.4.0 <4.0.0` and Flutter
`>=3.22.0`. CI pins Flutter 3.44.6 with Java 17; Android builds target
`minSdk 31` / `targetSdk 35`. If a build reproduces only locally, compare your
Flutter version against the pin in `.github/workflows/android-ci.yml` first.

**Firebase config.** `google-services.json` is deliberately untracked. The
Gradle build detects its absence and skips Google Services processing rather
than failing, so a local build works without it. CI builds the release APK only
when the `GOOGLE_SERVICES_JSON` secret is present.

For device-side setup, notification permissions, and WorkManager timing
behavior, see [`build-and-run.md`](build-and-run.md).

## What CI already checks

`.github/workflows/android-ci.yml` runs on every push and PR to `main`:
`flutter pub get`, `dart run build_runner build --delete-conflicting-outputs -d`,
then `flutter test`. On pushes with the Firebase secret configured it also
builds and uploads a release APK.

So compile breakage and test failures surface on the PR without anyone
remembering to check. Two things CI does **not** run, which still need a human
or a device:

- `flutter analyze` is not a CI step. Analyzer regressions can merge. Run it
  locally before pushing — a green baseline was restored deliberately in
  `chore: restore analyzer-green baseline (#27)` and is worth keeping.
- `flutter run` on real hardware. Nothing in CI exercises notifications,
  WorkManager, alarms, Health Connect, or the Wear surfaces.

Two further workflows guard the repo rather than the build:
`repo-hygiene.yml` (root clutter, committed artifacts, duplicate project trees)
and `stale-branch-report.yml` (weekly stale-branch issue).

## If you cannot run these commands

Agent/cloud containers for this repo generally have **no `flutter` or `dart` on
`PATH`**. That is expected, not a broken environment.

When you cannot run a step, report «Not executed.» Do not infer analyzer, test,
or build results from reading the code. This rule is the direct fix for the
failure mode described in the history section below, and it is binding — see
`AGENTS.md`, Verification Rules.

## Reporting discipline

Use exactly one of three words, per spec §16:

- **Verified** — you ran the exact command and it succeeded. Quote the real output.
- **Implemented, not yet Verified** — the code exists; this step was not reached.
- **Proposed** — design only, nothing written.

When something fails, paste the **actual** compiler or analyzer text, with file
paths and line numbers. "It didn't compile" is not a status report. Fix one
error at a time and re-run rather than batch-guessing several fixes, so you know
which change actually worked.

One distinction worth keeping precise: an editor's inline analyzer diagnostics
carry the compiler's authority. An AI assistant's *generative* suggestions do
not — those are inference until something actually compiles them.

If an error claims a file or symbol does not exist, check whether the file is
actually in the repo before concluding the design is broken. This project has a
documented history of confident architecture descriptions that corresponded to
no real file; a stale claim is the more likely explanation than a bug in
something that was genuinely built.

## What does not need to work

Correctly dormant or deferred — not breakage to chase:

- **Google Tasks/Calendar sync** — OAuth is not activated; dormant by design
  (§12.2). Calendar awareness beyond the Tier 0 weekday rule is scoped but
  unbuilt; see [`CALENDAR-INTEGRATION-SCOPE.md`](CALENDAR-INTEGRATION-SCOPE.md).
- **The Lexi on-device bridge** — no stable Flutter package for on-device
  inference exists yet. `MissingPluginException` on the `neuroflow/lexi` channel
  is the expected Phase-1 behavior; the app falls back to `NoOpPlanAdvisor` and
  stays fully usable. §14 top build risk.
- **Alarms and Wear method channels** — the `dev.neuroflow` Kotlin bridges are
  not registered in `MainActivity`, and `wear/` is not included in
  `android/settings.gradle.kts`. The `neuroflow/alarms` and `neuroflow/wear`
  channels therefore have no live native handler. Known seam, not a regression.
- **Health Connect beyond Steps** — permission declaration, availability
  mapping, and the permission lifecycle are implemented; bounded paged reads,
  transport mapping, persistence, change tokens, and background sync are
  accepted-but-unbuilt. See [ADR-007](adr/ADR-007-health-connect-ingestion-boundary.md).

---

## History — what this document originally tracked

Kept because the reasoning still explains why the verification rules above are
written the way they are.

**The reconciliation.** The first section of this file was a one-time procedure
for replacing a diverged `origin/main` from a git bundle, with a backup tag and
an isolation branch before any force-push. That operation is complete; the repo
has had a single reconciled lineage since. The account of how the divergence
happened is in [`archive/RECONCILIATION.md`](archive/RECONCILIATION.md).

**The native scaffolds.** This file once recorded that `flutter create` had
never been run and no `android/` or `ios/` directories existed. Both scaffolds
now exist. Android is the only supported and CI-verified target; `ios/` is
generated scaffolding that nothing tests or ships.

**The two flagged friction points**, both written from confident-but-unverified
knowledge and both now resolved by an actual compiler:

- `googleapis_auth`'s `AccessCredentials`/`AccessToken` constructor shape in
  `lib/platform/calendar/calendar_service.dart` — resolved by removal. That file
  does not exist; Calendar integration was descoped to a later tier before any
  service was written.
- `NetworkType.notRequired` vs `NetworkType.not_required` in
  `lib/platform/background/background_scheduler.dart` — resolved as
  `NetworkType.notRequired`, which is what the installed `workmanager` exports
  and what compiles today.

**The Drift schema.** The original text described generating from
`lib/platform/local/database.dart` at schema v5 with five tables. The database
now lives at `lib/data/database.dart` at **schemaVersion 7**, spanning tasks,
habits, routines, notes and mood, the sync queue, scheduling rules, Hevy import
tables, and the health-evidence family. Migrations are additive `onUpgrade`
branches, and every schema bump needs a migration test — the pattern is
`test/unit/health_v6_to_v7_migration_test.dart`.

**The CI that did not exist.** The closing note proposed that a pre-commit
analyzer hook and eventually CI "would make this kind of drift structurally
harder to reproduce — worth doing, not worth setting up before there's ever been
one successful local compile to protect." There has since been one, and CI now
exists. The pre-commit hook still does not, which is why `flutter analyze`
remains a local-discipline step rather than an enforced gate.
