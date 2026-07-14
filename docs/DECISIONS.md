# NeuroFlow — Architecture Decision Records

## ADR-007: Transition-First Reframing

**Date:** 2026-07-14
**Status:** Accepted (design-only; implementation gated on Alpha 1 evidence)

**Decision:**
NeuroFlow's core mission is reframed from task management to guiding people through life's transitions — "optimize for transitions, not tasks" becomes a first-order product filter alongside the existing locked principles. Transitions are modeled by extending `Routine` (no parallel `TransitionTemplate` model). Full record and rationale: `2026-07-14-transition-first.md`; UX spec: `transitions.md`; field-level mapping: `routine-evolution.md`.

**Enforcement:**
- This is Phase 3 work. No implementation before Alpha 1 has real-world evidence, without exception.
- Location and Bluetooth triggers are held pending an explicit privacy decision.

## ADR-006: Dependency Modernization Policy

**Date:** 2026-07-08
**Status:** Accepted

**Decision:**
Major dependency upgrades are performed one ecosystem at a time, with a green build (`flutter analyze`, `dart run build_runner build --delete-conflicting-outputs`) required before proceeding. Runtime libraries and build tooling are never upgraded in the same step unless strictly required by dependency resolution.

**Rationale:**
Mixed-ecosystem upgrades create compound failure states that are difficult to diagnose. Sequential upgrades with mandatory Green Gate verification ensure each change is independently validated before the next is introduced.

**Enforcement:**
- Each stage must pass `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`, and `flutter analyze` before proceeding.
- The builder is responsible for fixing generator syntax issues before qa-engineer signs off.
- Stages 1–5 of the Modernization Sprint are gated by this policy.
