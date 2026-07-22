# ADR-003: Sealed state machines

**Status:** Accepted  
**Date:** 2026-07-22

## Context

Flattened state classes with many nullable fields permit illegal combinations (e.g., loading + error + session plan). These caused crashes and unclear UI phases during the Today plan proposal work.

## Decision

Where a state machine has mutually exclusive phases, use Dart 3 sealed hierarchies so illegal combinations are unrepresentable.

Example pattern:

- `Loading` / `Unavailable` / `Ready` as distinct types
- Interaction axes (`outcome`, `needsAttention`, `isReviewing`) live only on `Ready`
- Transitions pattern-match first; methods are safe no-ops outside valid states
- Prefer immutable construction over public `copyWith` for external callers

## Alternatives Considered

- Single class with nullable fields + runtime asserts — rejected; illegal states remain representable and easy to construct by mistake.
- freezed — rejected; repository convention is no freezed (manual immutability / sealed).

## Consequences

- Exhaustive switches become possible.
- Controllers stay simpler and safer.
- New phases require explicit subtypes, making reviews clearer.

## Related Documents

- [ARCHITECTURE.md](../ARCHITECTURE.md)
- [docs/today_state_proposal.dart](../today_state_proposal.dart)
- [docs/today_screen_interaction_contract.md](../today_screen_interaction_contract.md)
