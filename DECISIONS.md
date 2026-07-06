# NeuroFlow — Engineering Decision Log

*The major architectural decisions, why they were made, what was rejected, and the trade-offs accepted. Read this before overturning any of them — each has a reason that isn't obvious from the code alone.*

---

## DEC-001: Four-layer architecture with hard import boundaries
**Decision:** Domain / Data / Executive / Presentation, plus an isolated Intelligence seam.
**Alternatives considered:** Flat feature-folders; MVC; putting AI calls wherever convenient.
**Why:** The project's earlier history was destroyed by *fictional architecture* — multiple AI contributors generating code for components that didn't exist, drift going undetected until runtime. Hard layer boundaries make drift a **compile-time** failure instead of a runtime surprise. The Executive importing domain-only means it *cannot* accidentally call AI.
**Trade-off accepted:** More files, more ceremony than a flat structure. Worth it — the boundaries are load-bearing, not decorative.

## DEC-002: Local-first Drift as single source of truth
**Decision:** All state lives in local SQLite via Drift. Google services (when added) are mirrors.
**Alternatives considered:** Cloud-first (Firebase); Google Tasks/Calendar as primary store.
**Why:** The user does field work with unreliable connectivity, and an executive-function tool must work *always*. A prosthetic that fails without signal is useless. Also: offline-first sidesteps a whole class of sync-failure UX.
**Trade-off accepted:** Sync (future) becomes a harder problem — reconciling local truth with remote mirrors. Accepted because core function must never depend on network.

## DEC-003: Deterministic Executive, AI behind a seam
**Decision:** `Executive.evaluate()` is pure and synchronous. AI enrichment happens via `PlanAdvisor.refine()`, called only in `TodayController`, wrapped to never throw.
**Alternatives considered:** AI generates the plan directly; AI woven into the planning logic.
**Why:** Two reasons. (1) An ADHD user needs a *stable* plan — same state, same plan, every refresh. Non-deterministic AI planning would give a different answer each time, which erodes trust. (2) The app must work with zero AI (`NoOpPlanAdvisor` default). AI is strictly additive; it can enrich but never break the morning.
**Trade-off accepted:** AI can only *refine* an already-complete deterministic plan, not author novel plans from scratch. This is a feature, not a limitation — it guarantees the floor.

## DEC-004: Typed tables, NOT a unified event model  ⚠️ REPEATEDLY CHALLENGED
**Decision:** Each entity (Task, Habit, Routine, Note, MoodLog) is its own Drift table with its own typed schema.
**Alternatives considered:** A single generic `TimelineEvent` table that all entities inherit from / write into — proposed multiple times by multiple contributors, most recently as an "emergency directive."
**Why rejected:** Collapsing typed tables into one generic event bag:
  - destroys the type safety that has caught real bugs,
  - throws away a schema that compiles green,
  - recreates the "one big flexible table → untyped mud at scale" anti-pattern,
  - makes every feature write through one path, so a bad event corrupts the record.
**The resolution:** The timeline (a planned feature) is a **read-only projection** — a Riverpod provider that queries across the typed tables and merges by timestamp into a `TimelineEvent` *presentation object*. Nobody writes a TimelineEvent. **Present as events; persist as types.**
**Trade-off accepted:** The timeline requires read-time assembly (a merge query) instead of a single-table read. Negligible cost; enormous safety gain. **This decision must not be reversed** — it's the load-bearing wall.

## DEC-005: Energy as 3 levels, not a 4-tag taxonomy
**Decision:** `EnergyLevel { low, medium, high }`.
**Alternatives considered:** A 4-tag system (deep-work / phone / low-energy / waiting) from an earlier spec.
**Why:** At the moment of capture, "how much juice does this need" is instinctive; a taxonomy forces a *decision*, and decisions at capture-time are exactly where ADHD capture dies. Three levels is a gut-feel gradient, not a categorization task.
**Trade-off accepted:** Less semantic richness for the planner. Worth it for capture friction.

## DEC-006: Two functional colors only
**Decision:** `#2FB083` (emerald = action) and `#D9A441` (amber = time-attention). Everything else is neutral greys.
**Alternatives considered:** A fuller palette; color-coded energy levels; the fictional `#00BFA5` teal from an earlier fake spec.
**Why:** Color as *signal*, not decoration. Emerald means "the thing to act on"; amber means "time matters here" (overtime, behind-pace, overdue). Two colors that each *mean* something beats a rainbow that means nothing. Energy levels use shape/glyph, not color, so color stays reserved for its two jobs.
**Trade-off accepted:** Visually plainer. That's the point — calm over clutter.

## DEC-007: Weekday scheduling as a compact string, not a join table
**Decision:** `Routines.activeDays` = a string of ISO weekday digits ("12345" = Mon–Fri). Null = every day.
**Alternatives considered:** A separate `RoutineSchedule` table with day rows.
**Why:** For a personal app with a handful of routines, a join table is over-engineering. A 7-char-max string is trivially queryable (`firesOn(date)` checks `contains`), needs no join, and migrates with a single `addColumn`.
**Trade-off accepted:** Not normalized. Fine at this scale; revisit only if routines grow complex scheduling needs (e.g. "every other Tuesday").

## DEC-008: Kind overtime vs. urgent pace — two tones from one primitive
**Decision:** The focus timer's overtime is gentle (amber, "still yours"). The routine pace banner for scheduled routines is urgent ("you're behind, leave by X").
**Alternatives considered:** One universal timer behavior.
**Why:** A hard external deadline (6 AM clock-in) genuinely needs urgency; a self-imposed task estimate (laundry) needs forgiveness. Same countdown math, deliberately different emotional tone, correct for each context. The banner only appears for routines with a scheduled departure — un-timed routines stay forgiving.
**Trade-off accepted:** Two code paths for time feedback. Justified — the contexts are genuinely different.

## DEC-009: Riverpod without code generation (for now)
**Decision:** Plain `Provider`/`StreamProvider`/`NotifierProvider`, hand-written. `riverpod_generator` is in dev-deps but unused.
**Alternatives considered:** `@riverpod` annotation + codegen.
**Why:** The provider graph is small enough to hand-write clearly, and it avoids coupling the build to another codegen step (Drift already needs `build_runner`). Keeps the mental model simple for a solo/small team.
**Trade-off accepted:** Manual provider boilerplate. Minor at this size. `riverpod_generator` can be removed from pubspec, or adopted later if the graph grows.

## DEC-010: workmanager pinned to 0.5.2 (no caret)
**Decision:** `workmanager: 0.5.2` exactly, not `^0.5.2`.
**Why:** The `^` caret let it float to a newer major where the `NetworkType` enum was renamed (`not_required` → `notRequired`), breaking the build. Pinning stops silent version drift.
**Trade-off accepted:** Manual bump required for updates. Deliberate — this is a case where drift caused a real break.
**Future implication:** If bumping workmanager past 0.6, update `background_scheduler.dart`'s `NetworkType.not_required` to the new casing.
