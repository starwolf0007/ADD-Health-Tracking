# NeuroFlow — Phase 2 Feature #1: Leave-By Countdown

**Why this exists:** Bryan ran the baseline, used the Morning Launch routine, and identified the gap himself — the focus timer counts UP and forgives overtime (right for laundry, wrong for a 6 AM clock-in). This is the fix: a departure countdown with behind-pace detection and haptic warnings. This is the first Phase 2 feature, built from real usage data, exactly as Gate 0.5 intended.

## What it does

For any routine with a **scheduled start time** (currently: Morning Launch at 5:00 AM), a banner appears at the top of the routine runner showing:
- **"Leave in X min"** — counts down to the computed departure time (5:38).
- **"N min behind pace"** — if the wall clock is past where the current step should have finished, it shows how far behind, in amber.
- **Haptic buzz at 5 min and 2 min** to departure — the wrist-tap idea, phone-side for now.

Routines with **no scheduled time** (laundry, dishes) show nothing — they stay forgiving. The banner is invisible unless a departure exists.

## Files in this update

| File | Change |
|---|---|
| `lib/presentation/widgets/routine_pace_banner.dart` | **NEW** — the countdown + pace engine. Self-contained leaf widget, owns its own 1-sec ticker, never rebuilds parent. |
| `lib/presentation/routine_screen.dart` | Added import + mounted `RoutinePaceBanner` at the top of the body Column. |
| `lib/data/routine_seeds.dart` | Morning Launch reworked: real steps (teeth 5, clothes 7, lunch 10, boots 4), an explicit **12-min buffer step**, and a zero-duration "Leave by 5:38" marker. Total = 38 min → departure lands exactly at 5:38 from a 5:00 start. |

## To apply

1. Drop the three files in (overwrite the two, add the new one).
2. No new dependencies, no codegen needed — this is pure Dart against existing contracts.
3. `flutter analyze` — expect zero errors (may show `prefer_const_constructors` infos, cosmetic).
4. **Re-seed to see it:** the routine seed only runs on first launch. Clear app data (Settings → Apps → NeuroFlow → Storage → Clear Data) then reopen, OR uninstall/reinstall. The reworked Morning Launch with the 5:00 schedule will appear in Routines.
5. `flutter run`.

## How to test it

Open the Morning Launch routine from the Routines tab. The banner should show at top with "Leave in X min" (the number depends on the current time relative to 5:00–5:38). To feel the behind-pace logic without waiting for 5 AM: the pacing compares now-vs-schedule, so it's most meaningful during the actual 5:00–5:38 window — but the leave-by countdown renders any time you open it.

## Known notes

- **Behind-pace math** only engages after the scheduled start time (5:00 AM). Before then, it just shows the leave-by countdown. That's intentional — you're not "behind" on a routine that hasn't started.
- **Haptics fire once each** per screen open, at the 5-min and 2-min gates. Reopening the routine resets them.
- **Watch mirror is Phase 3** — the wrist buzz is phone-side only right now, as agreed.
- The buffer is a **visible step**, not hidden. If Bryan flies through his tasks and hits the buffer early, he sees he has slack. That's better than burying it — it rewards being ahead.
