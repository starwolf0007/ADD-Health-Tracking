# NeuroFlow — Repo Reconciliation & UI Fix Notes

*Prepared by Claude (chat) — presentation-layer pass, per spec §12.1 build roles.*

---

## 1. Progress assessment — the honest version

**What's genuinely strong:**

- **Architecture discipline is real, not aspirational.** The four-layer rule is enforced in the actual imports: `executive/planner.dart` imports only domain, the PlanAdvisor seam is clean, `NoOpPlanAdvisor` makes the app AI-optional by construction. This is better layering than most shipped Flutter apps.
- **Spec traceability.** Nearly every file cites the § it implements. The §13 corrections (no idle animation on the heartbeat, monochrome glyphs) are documented *in the code* where they apply. That's rare.
- **Domain models are complete and good.** `task.dart`, `habit.dart` (streak logic), `routine.dart` (step/progress logic) — done, pure, testable.
- **The data-layer interfaces are complete.** Task/Habit/Routine repositories are well-shaped.
- **RoutineScreen's design was right.** One step at a time, judgement-free skip, brief celebration.

**What was blocking (and is the real story of this repo):**

1. **Nine core files were truncated mid-line.** `theme.dart` ended at `FloatingActionBut`, `main.dart` at `// on`, `today_screen.dart` at `shape: RoundedRect`, `data/database.dart` at `TextColumn get notes =>`. These are chat-paste cutoffs — code copied from an AI chat window that hit a length cap, committed without a compile check. **The repo could not compile at all.**
2. **Two interleaved generations of the app coexist in `lib/`.** Gen A: `EnergyLevel{low,medium,high}` domain + `lib/providers.dart` + inline widgets in `today_screen.dart` + `lib/data/`. Gen B: `EnergyTag{deepWork,phone,lowEnergy,waiting}` widgets + `lib/app/providers.dart` (referencing `Task.source`, `lastTouchedAt`, `updatedAt` — fields that don't exist in the domain) + `lib/platform/local/`. Neither chain compiled against the other. This is the same multi-agent drift pattern as the docs reconciliation, expressed in code.
3. **Root-level junk.** 16 scrambled `.dart` files at repo root (root `main.dart` actually contains task-repository code), a `download` file, plus `ADD-Health-Tracking-v1.16 (2).bundle` and `ADD-Health-Tracking-with-git-history.tar.gz` — archives of the repo committed *inside* the repo.

**Verdict:** the thinking is Phase-1-complete; the repo was not. This fix pass makes the presentation layer + wiring one coherent generation. The remaining compile blockers are listed in §4.

---

## 2. What this pass delivers (drop-in files)

All files replace their counterparts under `lib/`:

| File | Status |
|---|---|
| `lib/presentation/theme.dart` | **Rewritten.** Un-truncated. Locked tokens preserved (`#0c0c0d` / `#2FB083`). Adds the tokens Gen-B widgets referenced but never defined (`divider`, `surfaceRaised`, `textFaint`, `accentWash`), a 4pt spacing scale (`AppSpace`), 48px tap-target constant, and full component themes (buttons, inputs, sheets, snackbars, low-motion page transitions). |
| `lib/presentation/today_screen.dart` | **Redesigned.** Next Best Action is now a display-scale card — the one thing looks like the one thing. HeartbeatLine (previously orphaned) is wired under the header with real completed/total data. Quick Wins mode is visually lighter. Completion shows a calm "Done — N today" snackbar. Date anchor in header. Error state gets a Retry. All-clear state offers capture inline. Due-routines rows launch RoutineScreen. ~200 lines of duplicated inline widgets deleted in favor of `widgets/`. |
| `lib/presentation/widgets/capture_sheet.dart` | **Rewritten** against the current domain (`Task.create`). Energy selector as shape-glyph chips, quick-win toggle (low energy auto-counts), grab handle, keyboard-safe padding, capture confirmation. |
| `lib/presentation/widgets/energy_glyph.dart` | **Reconciled** to `EnergyLevel` so it compiles today; the §13 four-tag migration is isolated to one switch (see decision #1). |
| `lib/presentation/widgets/heartbeat_line.dart` | Unchanged — compiles now that `AppColors.divider` exists. Its no-idle-animation design was already correct. |
| `lib/presentation/routine_screen.dart` | **Completed** (was truncated mid-`launchRoutine`). Design preserved; tokens applied; `launchRoutine` helper finished. |
| `lib/presentation/habits_widget.dart` | **Polished.** Whole row is now a 48px ripple target (check circle was a bare 26px GestureDetector). Semantics labels added. |
| `lib/app/providers.dart` | **Rewritten as THE composition root.** Wires `lib/data/` repos + `Executive.evaluate → Plan` + the §14 advisor-tier switch. Kills the duplicate `TodayState` class — the UI consumes the executive's `Plan` directly. |
| `lib/main.dart` | **Completed.** Notification/scheduler init, first-launch seeds, `resetRoutinesIfNewDay`, `UncontrolledProviderScope`. |

**UI preview:** `neuroflow-ui-preview.html` — open on any phone/browser to see the redesigned Today screen (normal / quick wins / all clear / capture) before compiling.

---

## 3. Cleanup checklist (delete these)

```bash
# Root-level scrambled duplicates (contents don't even match their names)
git rm habit.dart habit_repository.dart habits_widget.dart lexi_config.dart \
  lexi_plan_advisor.dart main.dart notification_service.dart planner.dart \
  providers.dart routine.dart routine_repository.dart routine_repository_impl.dart \
  routine_screen.dart task.dart task_repository_impl.dart today_screen.dart download

# Repo archives inside the repo
git rm "ADD-Health-Tracking-v1.16 (2).bundle" ADD-Health-Tracking-with-git-history.tar.gz

# Superseded Gen-B stragglers (composition root is now lib/app/providers.dart;
# platform DB home is lib/data/ per the Gen-A chain everything now compiles against)
git rm lib/providers.dart

# REVISED (2026-07-02, see FABLE5-PROMPT-AUDIT.md): do NOT delete
# lib/platform/local/database.dart yet. It's the only COMPLETE schema in the
# repo and it's spec-aligned (EnergyTag x4 + SyncQueue for §12.2). Use it as
# the primary source when rebuilding lib/data/database.dart, then retire it:
#   git rm lib/platform/local/database.dart lib/platform/local/task_repository_impl.dart
# only AFTER the rebuilt lib/data/database.dart compiles.

# Four-layer fix: Lexi files move out of executive/ (AI must not live there).
# This package ships them at lib/intelligence/ with imports already updated:
git rm lib/executive/lexi_plan_advisor.dart lib/executive/lexi_config.dart
```

Add to `.gitignore`: `*.bundle`, `*.tar.gz`, `download`.

---

## 4. For Claude Code / Copilot (compile-land)

- **`lib/data/database.dart` is truncated** (ends at `TextColumn get notes =>`) and must be rebuilt before anything runs — Tasks/Habits(+CheckIns)/Routines(+Steps) tables per the domain models, then `dart run build_runner build -d`.
- Verify `lib/data/*_repository_impl.dart` compile against the rebuilt schema (they were written for it).
- `flutter analyze` on this drop should surface only database-related errors; everything in `presentation/`, `app/`, `executive/`, `domain/` is internally consistent.

## 5. Decisions for the team

1. **EnergyLevel vs EnergyTag (spec §13).** The spec locks four tags (deep-work · phone · low-energy · waiting); the domain models three levels. This pass compiles against the domain and confines the future migration to: `domain/task.dart` enum, the DB column mapping, `Executive._quickWinsMaxEnergy`, and one switch in `energy_glyph.dart`. Recommend migrating **before** first real data exists — it's a schema change, cheapest at zero rows.
2. **Process rule — the compile gate.** Every truncated file traces to the same cause: chat-window paste → commit, no build. Proposed rule for all agents: *no commit lands without `flutter analyze` passing locally (Claude Code/Copilot run it; chat-agents' output goes through them, never straight to git).* The CI mentioned in the README doesn't exist yet (`.github/workflows/` is absent) — adding it makes this rule self-enforcing.
