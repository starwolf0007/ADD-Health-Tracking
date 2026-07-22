# ADR-005: Passive presentation layer

**Status:** Accepted  
**Date:** 2026-07-22

## Context

Widgets that contain business rules or call repositories directly duplicate logic, break the executive’s single source of truth, and make UI tests fragile.

## Decision

`lib/presentation/` is a passive receiver of executive-owned (and projected) state.

- No business logic in widgets.
- No direct repository or Drift access from widgets.
- Widget-tree changes require explicit authorization.
- Projection helpers live in executive or app layers and feed the UI.

## Alternatives Considered

- Fat widgets / GetX-style controllers in presentation — rejected; scatters rules and couples UI to persistence.
- Shared “view models” that re-implement executive decisions — rejected; duplicates truth.

## Consequences

- UI can be swapped or redesigned with lower risk to behavior.
- Executive and unit tests cover the real rules.
- Presentation changes stay in scope when authorized.

## Related Documents

- [ARCHITECTURE.md](../ARCHITECTURE.md)
- CLAUDE.md layer map
