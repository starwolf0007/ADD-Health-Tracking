# NeuroFlow — Weekday Rules Update (+ Calendar Scope)

**Two things in this drop:**
1. **Weekday-aware routines** (BUILT) — Morning Launch now fires Mon–Fri only. No 5 AM alarm on Saturday.
2. **CALENDAR-INTEGRATION-SCOPE.md** — the forward plan for full calendar-awareness (vacation prep, day-off detection, etc). Design only, not built. Read it for the roadmap.

---

## ⚠️ This update changes the database schema — codegen MUST re-run

Added `Routines.activeDays` column → **schema bumped v1 → v2** with a migration. You must regenerate:

```bash
dart run build_runner build --delete-conflicting-outputs
```

The migration (`onUpgrade`) adds the column without data loss, so existing installs upgrade cleanly. But `database.g.dart` must be regenerated or it won't compile.

## Files changed

| File | Change |
|---|---|
| `lib/data/database.dart` | Added `activeDays` column to Routines; schemaVersion → 2; added `MigrationStrategy`. |
| `lib/domain/routine.dart` | Added `activeDays` field + `firesOn(date)` helper. |
| `lib/data/routine_repository_impl.dart` | Threaded `activeDays` through both mappers; `fetchDueNow` now skips routines that don't fire today. |
| `lib/data/routine_seeds.dart` | Morning Launch set to `activeDays: '12345'` (Mon–Fri). |
| `lib/presentation/routines_list_screen.dart` | Card shows the day pattern ("Weekdays") next to the time. **Also fixed** a `launchRoutine` call that used a named `routine:` arg — the function takes it positionally. |

## To apply

1. Overwrite the five files.
2. **`dart run build_runner build --delete-conflicting-outputs`** ← required, schema changed.
3. `flutter analyze` — expect zero errors.
4. **Re-seed to see it:** clear app data (Settings → Apps → NeuroFlow → Storage → Clear Data) then reopen, so the weekday Morning Launch seeds fresh. (Existing installs migrate the column automatically, but the *seed* only re-runs on a clean start.)
5. `flutter run`.

## How the weekday rule works

- `activeDays` is a compact ISO-weekday string: Mon=1 … Sun=7. `"12345"` = weekdays, `"67"` = weekends, `null` = every day (all pre-existing routines default to null = fires daily, unchanged).
- `fetchDueNow()` calls `routine.firesOn(now)` and skips routines that don't fire today.
- So Morning Launch (`"12345"`) simply won't surface Saturday or Sunday. The evening wind-down routine has no `activeDays`, so it still fires daily.

## Test it

- Open Routines — Morning Launch card should read "5:00 AM · Weekdays".
- On a weekend, Morning Launch should NOT appear in "Due now" on the Today screen. On a weekday during the 5:00 window, it should.

## What's NOT in this update (deliberately)

Full calendar integration (vacation prep, day-off auto-detection, Lexi scheduling) is scoped in CALENDAR-INTEGRATION-SCOPE.md but not built — it needs Google OAuth, which is its own phase after the week of real use. The weekday rule covers the highest-frequency case (weekday-only work routine) with zero integration cost.
