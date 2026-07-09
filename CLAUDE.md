# Flutter App Project Rules

## Tech Stack
- Flutter SDK (Android Target)
- Dart (Sound Null Safety)
- State Management: [Insert your choice, e.g., Riverpod / Bloc / Provider]

## Build & Development Commands
- Get dependencies: `flutter pub get`
- Run on device: `flutter run`
- Check issues: `flutter analyze`

## Guidelines
- Always prioritize Material 3 design widgets.
- Write clean, responsive UI layouts that adapt to different Android screen sizes.
- Handle all async calls with try-catch blocks and show user-friendly error indicators.

## File Placement

Where new files go, matching the README's docs map and the four-layer architecture (spec §3).

### lib/ layer map

```
lib/app/            Riverpod composition root — providers.dart, bootstrap.dart, achievements.dart
lib/domain/          Task/Habit/Routine/Note/Mood entities + repository interfaces — no Flutter/Drift/Google imports
lib/data/            Repository implementations + Drift database — depends on domain only
lib/executive/       Context, next-best-action, Quick Wins rules — depends on domain only, never imports lib/intelligence/
lib/intelligence/    Lexi on-device + optional cloud adapter — implements executive/planner.dart's PlanAdvisor
lib/platform/        Notifications, background work, sync, alarms, wear, settings — OS/device integration
lib/presentation/    Flutter UI — screens at the top level, shared widgets under presentation/widgets/
```

New code goes in the layer it belongs to, not the layer that's most convenient — domain and executive stay Flutter-free; only intelligence and platform touch native/cloud surfaces.

### docs/ subdirectory map

```
docs/            Living specs and references (build path, design system, connected services, decisions log)
docs/google/     Google integration architecture, setup, and auth docs
docs/archive/    Point-in-time handoff notes, session memos, and status snapshots — history, not current guidance
```

Root-level `.md` files are for `README.md` and `CLAUDE.md` only. Anything else — a new handoff note, a design memo, a status snapshot — goes into `docs/` or `docs/archive/`, never the repo root.

### scripts/

All `.bat` and `.ps1` helper scripts (e.g. `run_green_gate.bat`, `run_green_gate.ps1`, `diagnose.bat`) live in `scripts/`, not the repo root.

### test/ structure

```
test/unit/          Unit tests, one file per domain/executive concern (e.g. executive_test.dart, habit_test.dart, routine_test.dart)
test/widget_test.dart   Top-level widget smoke test
```

Mirror this pattern for new tests: unit tests for domain/executive/data logic go under `test/unit/`; widget-level tests stay flat under `test/` alongside `widget_test.dart` unless the suite grows large enough to warrant its own subdirectory.