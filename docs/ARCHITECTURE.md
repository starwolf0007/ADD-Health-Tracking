# NeuroFlow Architecture

**Status:** Living document  
**Audience:** Human owners and AI collaborators  
**Precedence:** Explicit owner authorization for the current task > ADRs > this document > AGENTS.md > agent defaults

A feature request does **not** implicitly authorize overriding an ADR or architectural invariant. Conflicts must be surfaced for approval.

---

## System purpose and goals

NeuroFlow is a native Flutter ADHD executive-function companion.  
Core philosophy: **rich engine, deceptively simple UI.**

Every feature is filtered by one question: does this reduce friction for the user, or does it merely add a feature?

Architectural goals:

- Local-first (Drift/SQLite is source of truth; cloud services are mirrors)
- Deterministic executive logic that works with AI absent or cold
- Illegal states unrepresentable where practical
- Minimal public surfaces and intent-driven controllers
- Tests as production assets

---

## Four-layer model

```
lib/domain/         Pure Dart entities + repository interfaces
                    No Flutter, Drift, Riverpod, or intelligence imports

lib/executive/      Decision logic, planners, day resolution, state machines
                    Pure Dart. Depends on domain only.
                    MUST NEVER import lib/intelligence/

lib/platform/       Drift, notifications, background work, Google/Health, OS

lib/presentation/   Flutter UI. Receives executive-owned state.
                    No business logic. No direct repository/DB calls in widgets.

lib/app/            Composition root (Riverpod providers, bootstrap)
                    The only place intelligence is wired in
```

`lib/intelligence/` implements optional advisors (Lexi / cloud). It is injected at the composition root; the default is a no-op identity.

See also: CLAUDE.md layer map and `docs/COPILOT_INSTRUCTIONS.md`.

---

## Permitted dependency directions

```
Presentation  →  Executive  →  Domain
     ↓               ↓
   App (composition) → Platform → Domain
     ↓
 Intelligence (injected only at App)
```

- Domain never depends outward.
- Executive never depends on intelligence or presentation.
- Presentation never contains business rules.

---

## Executive-layer responsibilities

- Pure decision logic (day resolution, planning, trust/voice copy, transitions)
- State machines for proposal/review flows
- Deterministic behavior independent of AI availability
- No Flutter imports; no debug gating that requires Flutter foundation

Related: [ADR-001](adr/ADR-001-pure-dart-executive-layer.md)

---

## Riverpod’s role

Riverpod owns lifecycle and dependency composition.

- Controllers are Notifiers (or the repo’s established Riverpod pattern)
- Initialization occurs through provider `build()` / injected seeds
- Tests interact via `ProviderContainer` with overrides
- No standalone mutable controllers that bypass the composition root

Related: [ADR-002](adr/ADR-002-riverpod-lifecycle-and-composition.md)

---

## State-machine philosophy

- Prefer Dart 3 sealed classes so illegal combinations are unrepresentable
- Axes that only make sense together live on the appropriate subtype
- Transitions are pure functions or controller methods that pattern-match first
- Public methods are safe no-ops when called in an invalid context
- No bangs on nullable fields that the type system already constrained away

Related: [ADR-003](adr/ADR-003-sealed-state-machines.md)

---

## Controller / public API style

Controllers expose **intent** methods only (acceptDay, startReview, notNow, undo, …).

- No public `copyWith` on state for external mutation
- No public lifecycle setters (`loadProposal`, `setLoading`, `setUnavailable`)
- Development/test seeding uses injected seeds or gated capabilities, not public setters

Related: [ADR-004](adr/ADR-004-intent-driven-controller-apis.md)

---

## Presentation-layer boundaries

- Widgets receive projected state; they do not own business rules
- No direct repository or Drift access from widgets
- Widget-tree changes require explicit authorization

Related: [ADR-005](adr/ADR-005-passive-presentation-layer.md)

---

## Intelligence / Lexi isolation

- AI is optional. The app must remain fully usable with intelligence unavailable.
- Executive never imports intelligence.
- Composition root injects a `PlanAdvisor` (default: no-op).
- Lexi may propose; only confirmed, gated actions mutate deterministic state.

Related: [ADR-006](adr/ADR-006-intelligence-is-optional.md)

---

## Testing boundaries

- Unit tests under `test/unit/` for domain/executive logic
- Tests are production assets: never replace executable tests with comments or placeholders
- ProviderContainer is the preferred way to exercise Riverpod controllers
- Verification reports only what was actually run against the committed tree

---

## Tech stack invariants (summary)

- Flutter native (Android target), Dart ≥ 3.4
- Plain Riverpod (no riverpod_generator for app state)
- Drift for persistence; codegen limited to Drift
- No freezed — manual immutable classes / sealed types
- Local-first; cloud services are mirrors

---

## Related documents

- [AGENTS.md](../AGENTS.md) — collaboration contract
- [docs/adr/](adr/) — Architecture Decision Records
- [docs/COPILOT_INSTRUCTIONS.md](COPILOT_INSTRUCTIONS.md)
- [docs/today_screen_interaction_contract.md](today_screen_interaction_contract.md)
- CLAUDE.md — file placement and layer map
