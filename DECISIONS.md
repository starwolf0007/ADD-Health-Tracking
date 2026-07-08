# NeuroFlow — Architecture Decision Records

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
