# Stage 3+2 — Ready for Green Gate

All code changes are complete. Please run the Green Gate:

**Double-click `C:\Dev\run_green_gate.bat`**

A terminal window will open, run for ~30 seconds, then close.
Results will be written to `green_gate_log.txt`.

Once done, reply in chat and I'll read the log and continue.

---

### What was changed

**pubspec.yaml**
- `flutter_riverpod: ^3.0.0` (from ^2.5.1)
- `riverpod_annotation: ^4.0.0` (from ^2.3.5)
- `riverpod_generator: ^4.0.0` (from ^2.6.5)
- `drift_dev: ">=2.28.2"` (from ">=2.18.0 <2.28.2")
- `build_runner: ">=2.15.0"` (from ">=2.4.0 <2.15.0")

**lib/app/achievements.dart**
- `StateProvider<bool>` → `NotifierProvider<AchievementsEnabledNotifier, bool>`

**lib/app/providers.dart**
- `StateProvider<AdvisorTier>` → `NotifierProvider<AdvisorTierNotifier, AdvisorTier>`

**lib/app/bootstrap.dart** + **lib/presentation/settings_screen.dart**
- 3 call sites: `.notifier.state = …` → `.notifier.set(…)`
