# ADR-002: Riverpod lifecycle and composition

**Status:** Accepted  
**Date:** 2026-07-22

## Context

State must have a single composition root. Standalone mutable controllers that bypass providers make testing and lifecycle (dispose, overrides, seed injection) inconsistent.

## Decision

- Riverpod owns lifecycle and dependency composition.
- Controllers follow the repository’s established Riverpod pattern (`Notifier` / `AsyncNotifier` as used in `lib/app/providers.dart`).
- Initialization occurs through provider `build()` reading injected seeds/dependencies.
- Tests use `ProviderContainer` with overrides; no public lifecycle setters on controllers.
- Codegen for Riverpod is not used for app state (codegen surface limited to Drift).

## Alternatives Considered

- Standalone mutable controller classes — rejected; breaks override/testability and hides lifecycle.
- riverpod_generator for all notifiers — rejected; repo deliberately limits codegen to Drift.

## Consequences

- Production and test initialization share the same path (seed/provider).
- Public controller surface stays intent-only.
- Adding a new controller requires a provider at the composition root.

## Related Documents

- [ARCHITECTURE.md](../ARCHITECTURE.md)
- [ADR-004](ADR-004-intent-driven-controller-apis.md)
