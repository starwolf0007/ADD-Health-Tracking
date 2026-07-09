# NeuroFlow

Calm-functional ADHD execution app. Native Flutter. Replaces NeuroList + RoutineFlow.

**Source of truth:** [`docs/NeuroFlow-Unified-Spec-v1.4.md`](docs/NeuroFlow-Unified-Spec-v1.4.md) — design principles, locked design tokens, Quick Wins/Focus mechanics, AI tiering.
**Build log:** [`docs/NeuroFlow-Build-Notes-v0.3.md`](docs/NeuroFlow-Build-Notes-v0.3.md) — stack decisions, §10 resolutions, open reviewer questions.

## Docs map

- `docs/` — living specs and references (build path, design system, connected services, decisions log)
- `docs/google/` — Google integration architecture, setup, and auth docs
- `docs/archive/` — point-in-time handoff notes, session memos, and status snapshots, kept for history but not current guidance
- `CLAUDE.md` — project rules read automatically by Claude Code

## Architecture (four layers, spec §3)

```
lib/presentation/   Flutter UI
lib/executive/       context, next-best-action, Quick Wins rules — depends on domain only
lib/platform/        notifications, background work, local DB, sync
lib/intelligence/    Lexi on-device + optional cloud adapter — implements executive/planner.dart's PlanAdvisor
lib/domain/          Task entity + repository interface — no Flutter/Drift/Google imports
lib/app/             Riverpod composition root (providers.dart)
```

**Hard rule:** Executive never imports `lib/intelligence/`. It runs a complete `DeterministicPlanner` with `NoOpPlanAdvisor` as the default Intelligence — see `lib/executive/planner.dart`.

## Status

Phase 1 spine: written, not yet compiled in this repo. Needs, in a real Flutter environment:

```bash
# Android-only scaffold (this repo is Android-first)
flutter create . --platforms=android
flutter pub get
dart run build_runner build -d              # generates database.g.dart (Drift)
```

`lib/intelligence/` is currently a seam — the on-device Lexi bridge (Apple Foundation Models / Gemini Nano) has no stable Flutter package and is written as a per-platform method channel. Top build risk — not started.

## Build roles (spec §12.1)

Claude (chat) writes Dart source. Gemini / ChatGPT / Grok review (architecture / layering / build-detail respectively). Bryan + Claude Code compile, device-test, and own OAuth/on-device-model bring-up.


---

Android notes

- This repository is targeted for Android only for now. The README commands above are narrowed to Android (`--platforms=android`) and the CI workflow (added at `.github/workflows/android-ci.yml`) runs Android-focused checks.
- The AndroidManifest includes permissions for notifications and WorkManager (see `android/app/src/main/AndroidManifest.xml`).

Local quick run (Android emulator or device):

```bash
flutter pub get
dart run build_runner build -d
flutter run -d <device-id>
# or build an APK
flutter build apk --release
```

CI

A GitHub Actions workflow has been added to run on every push/pull_request to `main` and performs `flutter pub get`, `dart run build_runner build -d`, and `flutter test` so PRs are validated for Android.

Next steps

- If you want I can: wire a small Android Kotlin method-channel stub so the Lexi bridge is callable from the app (I added a simple stub file under `android/app/src/main/kotlin/com/neuroflow/lexi/LexiBridge.kt`), and add a Dart wrapper under `lib/intelligence/lexi_bridge.dart` so the app code can call into the native bridge without crashing when the native side is absent.
- I can also add a small CI secret handling step if you later add cloud advisor keys (not added now).
