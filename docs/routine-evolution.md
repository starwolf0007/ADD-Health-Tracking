# Routine Evolution — Technical Mapping

**Status: Proposed.** No implementation. This document exists specifically to
prevent a `TransitionTemplate` class from being built as a parallel model —
see the reasoning in the original proposal
(`Transition-Routines-Proposal.md`, still the fuller architectural rationale;
this document is the concrete field-level mapping).

## What exists today

`Routine`: `id`, `name`, `anchor` (morning/midday/evening/custom),
`scheduleHour`, `scheduleMinute`, `isActive`, `createdAt`. `RoutineStep`:
`routineId`, `position`, `title`, `notes`.

## What gets added, and why each one is additive, not a new model

- **`trigger`** (new field, `RoutineTrigger` type): generalizes the existing
  `anchor`/`scheduleHour`/`scheduleMinute` time-only firing into the trigger
  taxonomy in `transitions.md`. Time-based routines keep working exactly as
  they do now — this is a superset, not a breaking change.
- **`boundedDurationMinutes`** (new, nullable field): when set, the routine
  gets the transition timer (bounded countdown) instead of no timer at all.
  Nullable and optional — existing routines without it are unaffected.
- **`focusSessionEnabled`** (new, nullable/boolean): opt-in flag, sits
  alongside the existing task stopwatch rather than replacing it. Gentle
  suggestion at the interval boundary (continue / break / save-and-stop),
  never a hard interrupt or automatic task mutation — resolved in
  `transitions.md`. Implementation should reuse the existing pause flow for
  "save and stop" rather than duplicating it.
- **`linkedTaskId`** (new, nullable field on `RoutineStep`): resolved —
  `Task` and `RoutineStep` stay distinct. A step may optionally reference an
  existing `Task` for the rare case where one step genuinely needs
  independent planning/tracking metadata; a step is never implicitly
  converted into a Task. One nullable column, backward compatible.
- **Completion copy** — resolved: a dedicated `RoutineCompletionCopy`
  abstraction, not an extension of `TrustVoiceCopy` (which was built around
  task-specific fields like `perceivedDifficultyBefore/After` that don't map
  onto routine completion). Four deterministic outcome states: `completed`,
  `goodEnough`, `paused`, `abandoned`. Deterministic first — must work
  without Lexi; she may optionally refine the wording later, never required
  to produce it. **`goodEnough` matters specifically:** it gives a routine
  permission to end well without every step completed, which is the
  no-shame principle applied somewhere it hadn't reached yet. **`abandoned`
  is fine as an internal state name** — same reasoning as
  `TransitionCoordinator`, internal names can be blunt since users never see
  them — **but the copy shown for that state needs the same no-shame
  scrutiny as everything else in the app.** A technical-sounding enum value
  doesn't exempt its user-facing text from the principle; this needs its own
  explicit pass when the copy is actually written, not an assumption that
  "abandoned" internally means anything harsher externally.
- **Adaptive history**: a query over past `RoutineStep` completion records
  for instances of the same routine template, not a new stored field —
  computed, matching the existing pattern used for stats aggregation
  elsewhere in the Executive layer.

## What explicitly does not get built

- No `TransitionTemplate` class.
- No new top-level "Transition Engine" subsystem. Internally, if a
  coordinating layer is needed once triggers beyond time exist, name it
  `TransitionCoordinator` — not `Context Engine`, which collides with the
  already-existing `ContextSnapshot` class in the Executive layer (the
  mood/sleep/HR/time-of-day bundle the planner already consumes). Users never
  see either name regardless.
- No location or Bluetooth trigger implementation until the privacy decision
  in `transitions.md` is made explicitly.
