# NeuroFlow — Unlock Sprint Memo

**Date:** 2026-07-27  
**Author:** Bryan (project owner) + Grok  
**Status:** Active  
**Audience:** All AI agents working on this repository (Claude, ChatGPT, Gemini, Grok, Codex, Devin, future agents)

---

## Why this exists

The spine is solid. CI is green. Architecture rules and process discipline got us here.

They are now the bottleneck.

Notes and Reflect are still pure placeholders (“coming in Phase 2”). Several integrations and the Lexi surface remain gated or silent. The result is an app that is not yet usable enough for daily dogfooding. The owner is drifting toward other ADHD tools because NeuroFlow does not yet deliver enough surface to compare, note bugs, and iterate in real life.

That defeats the premise of the project.

## Decision

We are running a controlled **Unlock Sprint** with these goals:

1. Make every primary surface (Today, Notes, Routines, Reflect, Settings / Connected Services / Health Integrations, Lexi conversation) **accessible and interactive**.
2. Prioritize daily-driver usability over process purity for the duration of the sprint.
3. Work **one surface at a time** to keep risk low and changes reviewable.
4. Produce a build the owner can install and use as primary scaffolding, note real bugs against, and compare to existing apps.

## What is temporarily relaxed

During this sprint the following process rules in `AGENTS.md` are **softened**:

- “Small, surgical changes over large rewrites” — larger, coherent presentation-layer changes are allowed when they unlock a complete surface.
- “Scope Discipline” / “Modify only files necessary” — related presentation + domain wiring for a single surface may be changed together when needed for usability.
- “Widget changes require explicit authorization” — authorization is granted for the unlock work described in this memo.
- Phase gating language (“coming in Phase 2”) is removed from user-facing screens. Incomplete seams must still be honest (clear labels, safe no-ops, or mock behavior) but must not hide the surface.

## What remains inviolable

These hard rules are **not** relaxed:

- Executive layer stays pure Dart and never imports `lib/intelligence/`.
- Intelligence remains optional (`NoOpPlanAdvisor` is the correct default path).
- Sealed-state architecture and repository conventions stay.
- Verification rules stay: never claim tests/analyzer/build success without running them. Report «Not executed.» when applicable.
- No fabricated success, no deleted tests, no placeholder-as-finished-work in committed code.
- Truth over appearance.

Any temporary layer leak or pragmatic stub introduced for speed must be documented in the PR / report and marked for later cleanup.

## Working method

- One surface at a time.
- After each surface is unlocked and verified, stop and confirm before moving to the next.
- Preferred order (subject to owner direction):
  1. Notes
  2. Reflect
  3. Settings / Connected Services / Health Integrations (make every control do something visible)
  4. Lexi conversation surface (mock or lightweight path so the companion feel is present)
  5. Remaining capture / Today / Routines dead-ends if any

## How other agents should behave

- Read this memo before large presentation or feature work.
- Prefer shipping a usable, honest surface over preserving every process constraint from the earlier spine phase.
- When in doubt, ask: “Does this change make the app more usable for daily dogfooding without breaking hard architectural invariants?”
- Continue to report accurately. Continue to keep Executive pure.
- When the sprint ends (owner declares usable daily-driver state reached), we restore full process strictness and clean up any temporary shortcuts.

## Reference

- This memo is the temporary override authority for process rules during the Unlock Sprint.
- Hard architecture (ADRs, Executive purity, Intelligence optional) is unchanged.
- See also the short note added to `AGENTS.md` and the entry in `docs/DECISIONS.md`.

---

End of memo.
