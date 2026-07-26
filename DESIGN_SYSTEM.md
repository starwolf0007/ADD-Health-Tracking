# NeuroFlow — Design System Trial Spec

## 1. Expanded Color Palette (Trial)
These colors are added to the baseline calm-functional palette for specific high-value signals.

| Token | Value | Meaning |
|---|---|---|
| `gold` | `#FFFFD700` | Achievement moments ONLY. High celebration, zero utility. |
| `info` | `#2196F3` | Informational state changes that aren't actions (e.g. sync status). |
| `lexi` | `#BB86FC` | Lexi's presence. Distinct from functional accent. |

## 2. Light Gamification Layer
Lightweight moments of celebration to reward "hard" actions without persistent scores or pressure.

### Principles:
- **Momentary:** Fires once, then vanishes.
- **Non-numeric:** No points, levels, or visible streaks.
- **Reversible:** Easily removed without data loss.

### Achievements:
- **RE-ENTRY COMPLETE:** Fires when a task that was previously `paused` or `blocked` is finished. Rewards the mental effort of returning to a context.

## 3. Rollback Plan
To revert this trial:
1. Delete `lib/app/achievements.dart` and `lib/presentation/widgets/achievement_toast.dart`.
2. Remove `AchievementToastHost` from `main.dart`.
3. Clean up the achievement block in `TodayController.complete()`.
4. Remove trial colors from `AppColors` in `theme.dart`.
