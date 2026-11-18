# ADR-004: Intent-driven controller APIs

**Status:** Accepted  
**Date:** 2026-07-22

## Context

Controllers that expose generic setters (`loadProposal`, `setLoading`, `setUnavailable`, public `copyWith`) allow callers to put the machine into arbitrary states and couple tests to internal shape.

## Decision

Public controller methods express **user or system intent** only (e.g., `acceptDay`, `startReview`, `toggleBlock`, `finishReview`, `keepOriginal`, `notNow`, `undo`, `keepDayOpen`).

- No public lifecycle setters.
- No public `copyWith` for external mutation of state.
- Seeding and unavailable paths are supplied via injected provider dependencies (or explicitly gated development methods that do not expand the production public surface).

## Alternatives Considered

- Rich public mutation API for flexibility — rejected; produces illegal states and weakens the sealed model.
- Reflection / dynamic state bags — rejected; opaque and untestable.

## Consequences

- Call sites read as the interaction contract.
- Tests initialize through seeds/overrides rather than setters.
- Adding a new intent is an explicit, reviewable change.

## Related Documents

- [ARCHITECTURE.md](../ARCHITECTURE.md)
- [ADR-002](ADR-002-riverpod-lifecycle-and-composition.md)
- [docs/today_screen_interaction_contract.md](../today_screen_interaction_contract.md)
