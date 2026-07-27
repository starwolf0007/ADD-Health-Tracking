# NeuroFlow — Architecture Decision Records

## ADR-008: Unlock Sprint — Temporary Process Relaxation for Daily-Driver Usability

**Date:** 2026-07-27  
**Status:** Accepted (time-boxed)

**Decision:**
For a controlled Unlock Sprint, process rules that prioritize small surgical changes, strict scope discipline, and phase gating on user-facing surfaces are temporarily relaxed. The goal is to make every primary surface (Notes, Reflect, Settings/Integrations, Lexi, etc.) accessible and interactive so the app can be dogfooded as a daily driver.

Work proceeds one surface at a time. Hard architectural invariants remain in force: Executive stays pure Dart and never imports Intelligence; Intelligence remains optional; sealed-state and repository conventions stay; verification rules (no unverified claims) stay.

**Rationale:**
The spine is complete and CI is green. Remaining process strictness is now the primary obstacle to real-world use. The owner is drifting to other apps because too many surfaces are still placeholders or gated. Usability for dogfooding is the current highest priority; process purity can be restored once a usable baseline exists.

**Enforcement / Duration:**
- Authority: `docs/UNLOCK-SPRINT-MEMO.md`
- Softened rules are listed in that memo and mirrored in `AGENTS.md`.
- Sprint ends when the owner declares a usable daily-driver state. Full process strictness is then restored and temporary shortcuts cleaned up.

---

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
