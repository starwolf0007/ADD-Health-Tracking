# ADR-006: Intelligence is optional

**Status:** Accepted  
**Date:** 2026-07-22

## Context

On-device and cloud AI (Lexi) are valuable enhancers but must never be required for core scheduling, tasks, routines, or timers. The product must remain usable when AI is unavailable, refused, or cold.

## Decision

- `lib/executive/` never imports `lib/intelligence/`.
- Intelligence is injected only at the composition root (`lib/app/providers.dart`) as a `PlanAdvisor` (or equivalent).
- Default implementation is a no-op identity (`NoOpPlanAdvisor`).
- Lexi may propose actions; only explicitly confirmed, gated proposal types may reach deterministic handlers.
- “Not now” and unconfirmed proposals cause no state mutation.

## Alternatives Considered

- Hard dependency on Gemini/Lexi for planning — rejected; violates offline and reliability goals.
- Executive calling intelligence directly — rejected; breaks pure executive and testability.

## Consequences

- Core flows work without AI.
- Proposal confirmation remains a user gate.
- New proposal types stay staged until deliberately enabled.

## Related Documents

- [ARCHITECTURE.md](../ARCHITECTURE.md)
- [ADR-001](ADR-001-pure-dart-executive-layer.md)
- docs/COPILOT_INSTRUCTIONS.md (intelligence isolation rule)
