# Design Trial — Expanded Colors + Achievement Layer

**Push this alongside or after Steps 1-2.** No schema change — pure Dart/theme, no codegen needed. Bryan requested trying an expanded palette and light gamification; this is built explicitly reversible per DESIGN_SYSTEM.md.

## What changed

| File | Change |
|---|---|
| `lib/presentation/theme.dart` | +3 trial colors: `gold` (achievements only), `info` (informational), `lexi` (Lexi's presence). Amber/emerald **unchanged** — they stay functional (time-attention, action). |
| `lib/app/achievements.dart` | **NEW.** The trial layer: `achievementsEnabledProvider` (kill switch), `AchievementKind` enum, `fireAchievement()` helper. No persisted score, no streak, no history — a moment fires once and is gone. |
| `lib/presentation/widgets/achievement_toast.dart` | **NEW.** Minimal gold toast, auto-dismisses after 3s. No badge shelf. |
| `lib/app/providers.dart` | `TodayController.complete()` now checks if the completed task was previously interrupted (paused/blocked) and fires the `reEntryCompleted` moment if so — the actual "you came back and finished it" signal. |
| `lib/main.dart` | Wraps `AppShell` in `AchievementToastHost` so moments can render. One mount point. |
| `DESIGN_SYSTEM.md` | **NEW.** The full trial spec, guardrails, and rollback plan. |

## Why this is safe to try
- **Amber and emerald are untouched.** The leave-by countdown and kind-overtime timer keep working exactly as before — nothing about their color meaning changed.
- **No schema change.** Pure Dart, no `build_runner` needed for this drop.
- **One flag kills it entirely.** `achievementsEnabledProvider` defaults `true`; flip to `false` (or just don't call `fireAchievement`) and the layer goes fully dark. Nothing else in the app reads achievement state.
- **No numeric score anywhere.** By design — this was the failure mode of every prior gamification proposal we rejected. This trial deliberately avoids it: no points, no levels, no streak that can break.

## To verify
```bash
flutter analyze     # expect 0 errors — no schema change, should be clean
flutter run
```

**To test the achievement moment:** pause a task (once the Re-Entry UI exists — for now, you can manually call `task.transitionTo(TaskState.paused, step: 'testing')` and save it via the repo, or wait for Step 3's Re-Entry Card which will make pausing a real UI action). Then complete that same task. A brief gold toast should appear top-of-screen: *"You came back and finished it. That's the hard part."* — then vanish after 3 seconds.

## If you don't like it
Revert is cheap and isolated:
1. Delete `lib/app/achievements.dart` and `lib/presentation/widgets/achievement_toast.dart`
2. Remove the `AchievementToastHost` wrap in `main.dart` (back to `home: const AppShell()`)
3. Remove the achievement-check block from `TodayController.complete()`
4. Remove the 3 trial colors from `theme.dart`
Nothing else references any of this — it's a clean lift-out.

## Review checkpoint
Same as every Phase 2 gate — revisit after real use. Specifically watch: does the gold moment feel earned, or does it feel like a notification you start dismissing without reading? That's the tell.
[lib](lib)