# ADR-009: Today Surface Contract

- **Status:** Proposed
- **Date:** 2026-07-29
- **Revised:** 2026-07-31 — see Correction below
- **Complies with:** `docs/NeuroFlow-Unified-Spec-v1.4.md` §155–170 (LOCKED v1.3)
- **Related:** ADR-005 (passive presentation layer), ADR-006 (intelligence is
  optional), ADR-008 (Unlock Sprint)

## Correction (2026-07-31)

The first version of this ADR required a manual, reversible "show the full
day" disclosure inside Quick Wins mode. That rule was drafted without
checking for existing repository doctrine on the same surface, and it
directly contradicted locked doctrine already in place:
`NeuroFlow-Unified-Spec-v1.4.md` §155–170 locks Quick Wins to
**automatic-only** entry and exit, with **no manual toggle of any kind**.

The conflict surfaced during the PR #55 device-gate review on 2026-07-31,
where a spec-compliant implementation was briefly flagged as a regression
against the (wrong) rule this ADR had introduced. The reversible-disclosure
rule is removed below. Nothing else in the review was affected — the
Executive-derived-activation principle (rule 6) and the commitments-stay-
visible principle (rule 7) were both unchallenged and are unchanged here.

The general lesson, not just the specific fix: new architecture proposed in
this repo needs to check `docs/adr/`, `docs/DECISIONS.md`, and
`docs/NeuroFlow-Unified-Spec-v1.4.md` for existing doctrine on the same
surface *before* being written, not after a conflict is found in review.

## Context

Today is the only screen that multiple workstreams want to add to: Quick
Wins, due routines, capture, Lexi, and eventually a return/recovery path.
Each addition is individually reasonable. Together, with no rule about what
belongs, they turn Today into the dense dashboard the product exists to
avoid.

This is not hypothetical. A repository audit on 2026-07-29 found two
surfaces already drifting:

- `AchievementToastHost` wraps the entire app in `main.dart`, but
  `fireAchievement()` is never called from anywhere. A mounted surface that
  cannot fire.
- `RoutineScreen` is orphaned — `AppShell` mounts `RoutinesListScreen`
  instead — alongside two unmounted widgets (`EnergyGlyph`, `HeartbeatLine`).

Both are the same failure: surfaces added without a rule for what Today and
its neighbours are *for*, and never removed when superseded.

## Decision

Today is governed by the following contract. Anything proposed for Today
must satisfy it or it does not ship. Where this contract and the locked
Quick Wins spec (§155–170) overlap, the spec's exact wording governs; this
document exists to extend that doctrine to the rest of Today, not to
restate or soften it.

### Purpose

> Today shows the smallest set of actions that can help begin, or return to,
> the day.

Not a summary of the day. Not a record of the day. A starting point.

### Content rules

1. **Every surface must offer an immediate action or genuine orientation.**
   Informational cards that do neither are removed, not restyled.
2. **Empty sections disappear entirely.** No zero-state filler, no "nothing
   here yet" placeholders occupying vertical space.
3. **Today-only elements render only when viewing the current date.** Anything
   derived from a same-day signal (mood, current time, active task) is scoped
   to today; browsing another date shows that date's real schedule.
4. **Quick Wins has no manual entry, exit, or disclosure control — none,
   ever.** Locked by spec §158/§170: "no separate screen, no manual filter
   toggle, no user action to trigger or maintain it." The mode is entered and
   exited only by signal (mood check-in, or the next day). This is stricter
   than a general "don't reconstruct the backlog" rule — it is a specific,
   load-bearing invariant: the day Bryan needs the reduction most is the day
   he has the least capacity to go find a toggle for it.
5. **A Quick Win completes on tap — no start, no timer, no in-progress
   state.** Locked by spec §167: "one-tap done." This is the one place in the
   app where tap-to-complete is correct; it does not generalize to the rest
   of Today's task rows.
6. **One primary action per card.** Secondary actions are permitted only when
   neutral and non-competing (for example "Not now"). The Quick Wins card's
   single tap-to-complete action already satisfies this — it does not need a
   second control.
7. **Presentation reads decisions, it does not make them.** Mode, ordering,
   and selection come from the Executive. A widget may not derive eligibility
   it could have been handed, and — per rule 4 above — it may not offer the
   user a way to override the Executive's mode choice either. (ADR-005)
8. **Commitments stay visible in every reduced view.** Fixed anchors and
   calendar events are never hidden to make a screen calmer — a calm screen
   that conceals a shift is a dishonest one. (Confirmed compatible with the
   locked spec: Codex's PR #55 review did not flag this, and device testing
   on 2026-07-31 confirmed anchors correctly remain visible inside Quick
   Wins.)

### Emotional rules

9. No streaks, scores, XP, completion percentages, or counts of failure.
10. No guilt or pressure language. "Due" is permitted; "overdue", "missed",
    "you forgot", and "behind" are not.
11. No congratulatory clutter for ordinary actions.
12. **Return paths are as prominent as starting paths.** Resuming paused
    work is a first-class action, not a recovery afterthought. This connects
    to the spec's resurfacing-pass principle (§ Stale-task sweep): "frictionless
    capture is just a nicer way to forget things" without a path back.

Rule 12 has a consequence worth stating plainly, because it has already been
misread once: *reinforcing a return is not gamification.* A one-time,
unpersisted acknowledgement that someone came back to interrupted work is
aligned with this contract. A streak, which punishes the break, is not. The
distinction is whether the mechanism rewards **returning** or rewards
**not stopping**.

### Surface order

Order expresses priority and is expected to be revised after daily-driver use.
The current intended order:

1. Day orientation (date, one-line summary)
2. Due routines
3. Quick Wins — when the Executive has activated the mode (per rule 4, this
   replaces 4 and 5 below, not adds above them, and offers no way out except
   the signal that put it there)
4. Active, paused, or recommended work
5. Fixed commitments and the timeline
6. Capture entry point
7. Reflection — only when contextually relevant

## Consequences

- Adding a surface to Today now requires naming which rule justifies it.
- Two existing findings become actionable: the unfired achievement layer must
  be either wired or removed, and `RoutineScreen` must be deleted or
  promoted.
- Rule 12 protects the return-path acknowledgement from being deleted by a
  future doctrine sweep, which was a live risk given its "gamification
  trial" labelling.
- Rule 2 conflicts with any future "empty state" design work. That is
  intentional.
- Rule 4 means Quick Wins can never grow an escape hatch, even a
  well-intentioned one. Any future proposal to add one must amend the locked
  spec first, not add a toggle to the widget and call it presentation detail.

## Not decided here

- Whether a mood check-in belongs on Today itself, or stays on Reflect. The
  Reflect write path works; proximity is a separate question that should be
  answered from device use, not from argument.
- Final surface ordering, pending further Pixel use.
- The pushed bad-day nudge (spec §167, "fix A") — Home Assistant / Assistant
  routine integration is out of scope for this ADR and for the current
  Unlock Sprint milestone.
