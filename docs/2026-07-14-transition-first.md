# 2026-07-14 — Transition-First Reframing

**Decision:** NeuroFlow's core mission is reframed from task management to
guiding people through life's transitions. "Optimize for transitions, not
tasks" becomes a first-order product filter, alongside — not replacing — the
existing locked principles.

## What prompted it

A real moment of friction, not a brainstorm: arriving somewhere new and
starting to unpack, without a clear sense of what "done" looked like.

> "I started unpacking, but I couldn't figure out how to finish."

That sentence is more than an anecdote. It names a specific, recurring
pattern this project had seen before without naming it precisely: start an
activity with no visible finish line, drift into something else, lose the
original context, never feel done, feel guilty about the fact that it never
resolved. The fix isn't "be more disciplined about unpacking" — it's that the
activity was never given a finish line in the first place.

## What was already built that this explains, in retrospect

- Re-entry notes (preserving a return point so "come back later" feels safe)
  were solving a transition problem without being named as one.
- Routine anchors (Morning start, etc.) were already transition templates in
  substance, just not framed that way.
- The Trust Voice completion-message pattern already existed for tasks; this
  decision extends the same instinct — specific, evidence-based, calm
  acknowledgment — to transitions.

## What was decided, specifically

1. Extend `Routine`, do not create a parallel `TransitionTemplate` model —
   see `routine-evolution.md`.
2. Every transition defines a visible finish *state*, not an activity
   description — see `core-principles.md`.
3. Location and Bluetooth triggers are held pending an explicit privacy
   decision, held to the same standard health data already received.
4. Three timers with three distinct jobs (transition / focus session /
   stopwatch) rather than one timer trying to serve every case.
5. This is Phase 3 work. It does not touch the Alpha stabilization branch.
   The standing rule — no Phase 2/3 work before Alpha 1 has real-world
   evidence — applies here without exception, regardless of how strong the
   idea is.

## Why this is recorded, not just implemented

So a future contributor asking "why does a Routine have a trigger field
instead of just a schedule time" finds the reasoning, not just the diff.

## Update — architecture questions resolved

The four items left open in `transitions.md`/`routine-evolution.md` at the
time this decision was first written are now resolved:

1. `Task` and `RoutineStep` stay distinct; `RoutineStep.linkedTaskId`
   (nullable) covers the rare case needing independent tracking.
2. Internal name is `TransitionCoordinator`, never surfaced in UI.
3. Focus Session is opt-in, sits alongside the task stopwatch, gentle
   boundary (continue/break/save-and-stop), no forced interruption or
   mutation — "save and stop" should reuse the existing task pause flow
   rather than duplicate it.
4. The transition-friction filter is confirmed necessary-not-sufficient,
   folded explicitly alongside autonomy, no shame/gamification, cognitive
   load, AI-optional, suggest-never-mutate, and phase-authorization.
5. Completion copy is a dedicated `RoutineCompletionCopy`, deterministic
   first, four outcomes (`completed`/`goodEnough`/`paused`/`abandoned`).
   `goodEnough` extends the no-shame principle to partial completion.
   `abandoned` stays as an internal-only label; its actual copy still needs
   the same no-shame review as everything else — the internal name doesn't
   grant the user-facing text an exemption.

**Implementation remains unauthorized until the Alpha evidence gate is
complete.** Resolving the architecture doesn't change the phase gate — this
is still Phase 3, and the standing rule from the original decision still
applies without exception.
