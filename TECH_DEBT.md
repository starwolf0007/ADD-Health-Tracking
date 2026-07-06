# NeuroFlow — Technical Debt Register

*Every known limitation, workaround, and refactoring opportunity in the current codebase. Nothing hidden. Honestly assessed severity.*

---

## Compile / build status
**As of last verification: compiles green.** `flutter analyze` → 0 errors (only `prefer_const_constructors` info-level lints, cosmetic); `flutter test` → 36 passing; `build_runner` regenerates `database.g.dart` at schema v3. Current through Phase 2 Steps 1–2 (living-state tasks + timeline projection). Runs on Pixel. The items below are debt, not breakage.

---

## Known limitations (by design, documented so nobody "fixes" them wrongly)

### TD-01 — Lexi advisor is a NoOp until the Gemini Nano SDK is wired
**Severity: expected / not a bug.**
`LexiPlanAdvisor` calls a method channel (`neuroflow/lexi`) whose native side (`LexiBridge.kt`) returns stubs (`checkGeminiNanoAvailable` → false, `generateResponse` → null). The advisor degrades gracefully to returning the plan unchanged. **To activate:** integrate Android AICore / Gemini Nano SDK in `LexiBridge.kt` at the TODO anchors. Requires on-device testing on a Nano-capable Pixel. Do not attempt without hardware.

### TD-02 — Focus timer haptics are foreground-only
**Severity: known limitation, Phase 2 polish.**
The halfway / 2-min / target haptic milestones in `focus_timer.dart` fire only while the app is foregrounded. Background firing (the wrist-buzz-while-phone-in-pocket experience) needs a lifecycle hook into `NotificationService` with scheduled local notifications at the milestone times. Marked `TODO(device)` in the file. Deferred deliberately — it needs tuning on the actual device/watch, not guessing.

### TD-03 — Seeds only run on first launch
**Severity: minor UX friction during development.**
`seedDefaultRoutines`/`seedDefaultHabits` run once on a fresh DB. Changing seed content (e.g. updating Morning Launch) requires clearing app data to see the change. Fine for production; mildly annoying in dev. A "reseed" debug affordance could help but isn't worth building yet.

### TD-04 — No sync layer exists
**Severity: expected / Phase 3 scope.**
`google_sign_in`, `googleapis`, `flutter_secure_storage` are in pubspec but **entirely unused** — zero sync code. `CloudGeminiPlanAdvisor.refine()` is a stub returning the plan unchanged. This is correct for the current phase (local-first baseline). Sync is a deliberate future phase, not missing work.

---

## Real debt (should be addressed, in rough priority order)

### TD-05 — Partial test coverage
**Severity: medium. Reduced from the original "no tests at all."**
A unit-test suite now exists and passes (36 tests, `flutter test` green): the Executive (`evaluate()` — Quick Wins trigger, mode selection, ordering) and the Habit/Routine domain models. Still unwritten, in rough priority:
1. Repository CRUD against an in-memory Drift DB (`AppDatabase.forTesting`).
2. `Routine.firesOn()` weekday logic.
3. Focus timer milestone firing.
4. Living-state transitions (`Task.transitionTo`, `TaskState.allowedNext`) and the v2→v3 migration.
The determinism of the Executive made its tests straightforward; the remaining targets are I/O- or widget-bound, which is why they lag.

### TD-06 — `today_screen.dart` is 677 lines
**Severity: medium.**
The largest file. It holds the Today screen plus several private widgets (`_NextBestAction`, `_FocusTimerStart`, `_FocusTimerActive`, `_MinuteChip`, quick-wins rows, due-routines section). It works and is coherent, but it's a candidate for extracting the focus-timer widgets into `widgets/`. Not urgent; do it when touching that screen anyway.

### TD-07 — Riverpod generator in deps but unused
**Severity: low / cleanliness.**
`riverpod_annotation` + `riverpod_generator` are in pubspec but nothing uses them (providers are hand-written — see DEC-009). Either remove them from pubspec or adopt codegen. Harmless as-is, just noise.

### TD-08 — Provider invalidation on task completion is implicit
**Severity: low, works correctly, worth understanding.**
`TodayController.complete()` calls `markComplete()` on the repo; the UI updates because `pendingTasksProvider` is a *stream* that Drift re-emits on write, which re-runs `build()`. This is correct and idiomatic, but the causal chain is implicit (no explicit invalidation). A new engineer should understand it's stream-driven, not manually refreshed.

### TD-09 — `dueRoutinesProvider` is a FutureProvider, not reactive
**Severity: low.**
Unlike the streams, due-routines is a `FutureProvider` re-evaluated on rebuild, not a live stream. Fine for its use (checked when Today builds), but if routines need to appear/disappear live as time crosses their anchor window, this would need to become time-aware. Currently acceptable.

### TD-10 — MainActivity package assumption
**Severity: low, one-time setup risk.**
`MainActivity.kt` and `LexiBridge.kt` assume package `com.neuroflow`. If `flutter create` generated a different applicationId, these must match or the channel won't register (throws `MissingPluginException`, which the advisor catches → permanent NoOp). Documented in the handoff; just verify on setup.

### TD-11 — TimelineScreen built but not wired into navigation
**Severity: low / intentional, Phase 2 in progress.**
`lib/presentation/timeline_screen.dart` (the read-only "Your Day" projection proof) compiles and renders `timelineProvider`, but it is not yet added to `app_shell.dart` navigation — deliberately, to keep the Phase 2 Step 2 drop reviewable. The next drop wires it in alongside the Re-Entry Card. Until then it's reachable only by direct construction.

---

## Performance notes
- **No known performance problems** at current scale. The app is small, streams are narrow, Drift queries are simple.
- The focus timer and pace banner each own a 1-second `Timer.periodic`. Both are leaf widgets that call `setState` on themselves only — they do NOT rebuild parents. Verified. If more per-second tickers get added, watch for rebuild scope creep.
- When the timeline is built: the merge-projection query will touch multiple tables. Keep it filtered (MVP scope) and consider caching if it ever feels heavy. Not a concern until it exists.

---

## Security / privacy notes
- **No secrets in code.** No API keys, no tokens committed. Future OAuth credentials go in `flutter_secure_storage`, never in source. (One OAuth client ID was once pasted into a planning conversation — if that project's credentials are reused, consider regenerating. Not in the codebase.)
- **`MoodLogs` has no sync columns** — sensitive data is structurally prevented from mirroring. If mood-sync is built later (user has expressed wanting it → Google Health), it must be an explicit, opt-in mirror, and the sensitive-data gate should be a conscious design step, not an accident.
- `flutter_secure_storage` is in deps, ready for when tokens exist.
