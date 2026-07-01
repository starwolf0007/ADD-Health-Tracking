# NeuroFlow

Calm-functional ADHD execution app. Native Flutter. Replaces NeuroList + RoutineFlow.

**Source of truth:** [`docs/NeuroFlow-Unified-Spec-v1.4.md`](docs/NeuroFlow-Unified-Spec-v1.4.md) — design principles, locked design tokens, Quick Wins/Focus mechanics, AI tiering.
**Build log:** [`docs/NeuroFlow-Build-Notes-v0.2.md`](docs/NeuroFlow-Build-Notes-v0.2.md) — stack decisions, §10 resolutions, open reviewer questions.

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
flutter create . --platforms=android,ios   # scaffolds android/ ios/ native shells (not in this commit)
flutter pub get
dart run build_runner build -d              # generates database.g.dart (Drift)
```

`lib/intelligence/` is currently empty — the on-device Lexi bridge (Apple Foundation Models / Gemini Nano) has no stable Flutter package and is written as a per-platform method channel. Top build risk, see spec §14.

## Build roles (spec §12.1)

Claude (chat) writes Dart source. Gemini / ChatGPT / Grok review (architecture / layering / build-detail respectively). Bryan + Claude Code compile, device-test, and own OAuth/on-device-model bring-up.
