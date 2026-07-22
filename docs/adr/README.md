# Architecture Decision Records

This directory records architectural decisions that are considered stable unless explicitly redesigned with owner approval.

## Template

Each ADR should contain:

- **Status** (Proposed | Accepted | Superseded | Deprecated)
- **Context**
- **Decision**
- **Alternatives Considered**
- **Consequences**
- **Related Documents**

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](ADR-001-pure-dart-executive-layer.md) | Pure Dart executive layer | Accepted |
| [ADR-002](ADR-002-riverpod-lifecycle-and-composition.md) | Riverpod lifecycle and composition | Accepted |
| [ADR-003](ADR-003-sealed-state-machines.md) | Sealed state machines | Accepted |
| [ADR-004](ADR-004-intent-driven-controller-apis.md) | Intent-driven controller APIs | Accepted |
| [ADR-005](ADR-005-passive-presentation-layer.md) | Passive presentation layer | Accepted |
| [ADR-006](ADR-006-intelligence-is-optional.md) | Intelligence is optional | Accepted |

Note: An earlier dependency-modernization decision lives in `docs/DECISIONS.md` (also labeled ADR-006 there). New formal records use this directory; numbering here is independent and focused on core layer boundaries.

## Hierarchy reminder

Explicit owner authorization for the current task (including authorization to supersede an ADR)  
→ ADRs  
→ [ARCHITECTURE.md](../ARCHITECTURE.md)  
→ AGENTS.md  
→ agent defaults

A feature request does not implicitly authorize overriding an ADR.
