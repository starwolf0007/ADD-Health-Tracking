# Transitions — UX Specification

**Status: Proposed.** Design-only. Not authorized for the current Alpha
stabilization branch — see `routine-evolution.md` for what changes when this
is built, and the standing rule: no Phase 3 work before Alpha 1 has real-world
evidence behind it.

## The hierarchy, and a boundary that's now resolved

```
Life State  →  Transition  →  Routine  →  Steps
```

Four levels, not five. **"Task" is deliberately not a level in this
hierarchy** — it's a separate, heavier-weight concept in the actual codebase
(`Task`: `perceivedDifficulty`, `actualMinutes`, `startedAt`, capture-rail
metadata) from `RoutineStep` (lighter, no independent tracking beyond the
routine's own progress). **Resolved:** the two stay distinct. A `RoutineStep`
may optionally carry a nullable `linkedTaskId`, pointing at a real `Task` when
one specific step genuinely needs independent planning/tracking — a step is
never implicitly converted into a Task. Small, safe migration: one nullable
column on `RoutineStep`, backward compatible, no forced complexity on steps
that don't need it.

## Life states are not a new persisted concept

A "life state" (at the hotel, cooking dinner, winding down) is a framing
device for *why* a transition exists — it does not need its own table or
class. It's context for the trigger and the copy, not a new piece of app
state to track and keep in sync with everything else.

## Every transition has a visible finish line

Not the activity — the state reached. "The room is functional," not "unpack."
See `core-principles.md`. This governs the goal text on every transition;
it's a copy discipline as much as a design one.

## Triggers

| Trigger | Status |
|---|---|
| Manual | Buildable now — trivial. |
| Time | Already exists (`Routine.scheduleHour`/`scheduleMinute`). |
| Calendar event | Calendar integration already dormant-built (spec §7); wiring near an event boundary is a small extension. |
| Watch shortcut | The Wear OS companion already exists (`wear/`); a genuine near-term extension. |
| Location | **Held.** Real privacy weight — geofencing reveals home address and travel patterns. Needs its own scoped privacy decision before design work starts, held to the same standard health data already got. |
| Bluetooth state | **Held.** Same reasoning — background BLE scanning has its own permission model (requires location permission on many Android versions) and needs the same explicit pass. |

**The interaction pattern for any inferred trigger, once one is built:** never
silently start a transition. Ask. *"Looks like you've arrived somewhere new.
Start a Hotel Arrival routine?"* — this is the existing suggest-never-mutate
principle (`core-principles.md`) applied to location/context inference, not a
new rule invented for this feature.

## Three timers, three different jobs

1. **Transition timer** — 5–15 min, bounded, never open-ended. Directly
   prevents the sprawl pattern already documented in Bryan's Mind Manual
   findings ("interesting projects can expand and consume an entire day").
   Deliberately the opposite of the task stopwatch's philosophy — a bounded
   countdown is correct here specifically because the job is preventing drift,
   not protecting focus from failure-framing.
2. **Focus session** — 20–45 min, Pomodoro-like, sustained work. **Resolved:**
   opt-in, sits alongside the existing task stopwatch — does not replace it.
   The interval boundary is a gentle suggestion, never a hard interrupt: at
   the boundary the user chooses continue, take a break, or save and stop.
   No automatic failure, forced break, or task mutation. **Integration point
   to confirm at implementation time, not assumed:** "save and stop" should
   almost certainly reuse the existing pause-with-optional-notes flow already
   built for tasks, rather than becoming a second, parallel "stop this task"
   mechanism that happens to look similar.
3. **Stopwatch** — passive, counts up, already built. Unchanged.

## Adaptive step suggestion is deterministic, not an AI feature

"You usually only unpack chargers and toiletries at hotels" is frequency
counting over past instances of the same routine template — pure Executive
layer logic, no AI dependency. Lexi may *narrate* the suggestion later; she
must never be required to *compute* it (`core-principles.md`, AI stays
optional).

## Example: a chained sequence

```
Hotel Arrival → 10-min transition → Room Ready
   → Relaxation → Dinner Reservation → Evening Wind Down → Bedtime
```

Nothing new is required to build this — it's a sequence of Routines, each
with its own finish line. The value is in the framing (a day of calm
transitions, not a pile of unrelated tasks), not in new architecture to
support the chaining itself.
