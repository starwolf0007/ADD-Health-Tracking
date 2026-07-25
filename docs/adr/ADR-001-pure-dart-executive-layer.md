# ADR-001: Pure Dart executive layer

**Status:** Accepted  
**Date:** 2026-07-22

## Context

Executive logic (planning, day resolution, proposal state machines) must remain testable and deterministic without a device or Flutter runtime. Past parallel implementations mixed UI and decision concerns, making behavior hard to verify and easy to break when AI or platform code changed.

## Decision

`lib/executive/` is pure Dart. It depends only on `lib/domain/`. It must never import Flutter, Riverpod, Drift, or `lib/intelligence/`.

Debug/test capabilities that need gating use pure-Dart injected capabilities or compile-time mechanisms, not `kDebugMode` or other Flutter foundation imports inside executive code.

## Alternatives Considered

- Allow Flutter imports for convenience of `kDebugMode` — rejected; couples executive tests to Flutter and breaks pure unit testing.
- Move state machines into presentation — rejected; business rules would live in widgets.

## Consequences

- Executive unit tests run without a device.
- Intelligence remains injectable and optional.
- Any future need for platform-aware executive behavior must go through injected ports, not direct imports.

## Related Documents

- [ARCHITECTURE.md](../ARCHITECTURE.md)
- [ADR-006](ADR-006-intelligence-is-optional.md)
