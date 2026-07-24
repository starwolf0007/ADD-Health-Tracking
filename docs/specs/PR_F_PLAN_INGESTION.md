# PR F: Plan Ingestion — Coach PDF/Excel → Hevy Workout Templates

**Status:** Approved architecture — BLOCKED on PR E (Verified)
**Reviewed by:** Claude, ChatGPT, Grok, Gemini (three-way convergence, 2026-07)
**Supersedes:** none
**Depends on:** PR B–E (Hevy cache hardening, incremental sync, analytics projections) merged and Verified

---

## 0. Purpose

Take a coach-authored monthly training plan (PDF or Excel) and turn it into fully-specified Hevy routines — sets, loads, set types, supersets, rest timers — without manual data entry and without silent misinterpretation.

This is a **write-direction** counterpart to the Phase 2 Hevy work, which is read-direction. It reuses the same sync boundary rather than opening a second path to the Hevy API.

---

## 1. Module Boundary

`PlanIngestion` is a bounded module parallel to the Executive Engine and Health Intelligence.

- It does **not** import Executive.
- It does **not** import Health Intelligence.
- It talks to Hevy **only** through the existing PR B–E sync layer.

### Non-goal (explicit)

Parsed plans do **not** become `HealthTransaction` evidence and never enter Health Intelligence tables. They are a separate input domain. No evidence tier, no vault classification, no correlation machinery applies here.

---

## 2. Pipeline

Strictly staged. Each stage is independently unit-testable and has its own test seam. Exercise-template lookup **must not** occur inside the raw extractor.

```
source file (PDF/XLSX)
  → 1. structural extraction      (raw text/tables only — deterministic, no interpretation)
  → 2. normalized plan syntax     (sets/reps/load/RPE/superset structure in canonical form)
  → 3. resolution candidates      (exercise name → Hevy template ID, with scores)
  → 4. ambiguity review           (human gate; local overrides consulted first)
  → 5. approved immutable plan    (no further mutation permitted)
  → 6. write executor             (sole caller of the Hevy sync layer)
```

### Stage 3/4 resolution order

1. **Local user-override table** (Drift) — user-confirmed mappings, scoped to this user
2. **Canonical ruleset** — repo-owned aliases and defaults
3. **Ambiguity gate** — anything unresolved by 1 or 2

---

## 3. Confidence Policy (deterministic, not model judgment)

The parser may emit scores. The **gate** uses fixed conditions:

| Condition | Outcome |
|---|---|
| Exact normalized alias match | Auto-resolve |
| Single high-confidence fuzzy match above threshold | Auto-resolve |
| Multiple plausible candidates | **Review required** |
| Unknown exercise name | **Review required** |
| Unsupported / unparseable notation | **Review required** |
| Set/rep/load parse throws format exception | **Review required** |

Thresholds are configuration, versioned with the ruleset, and covered by tests. A model confidence value alone never authorizes a write.

---

## 4. Canonical Ruleset

**Location:** `docs/skills/plan_ingestion_rules.md` (human-readable policy and edge cases)
**Optional companion:** `assets/plan_ingestion/plan_ingestion_rules.yaml` (machine-readable aliases/defaults, if runtime needs strict determinism)

Requirements:

- Git-tracked and PR-reviewable
- Versioned; every parse records the `rulesetVersion` it ran under
- Ships with the application — **production behavior must not depend on an external, AI-tool-specific skill directory**
- Contains a changelog section for rule additions

A Claude Code skill directory may hold a *development wrapper* describing how to edit or validate the rules. It is not the canonical source.

---

## 5. Domain Objects

```
PlanIngestionDraft      — extraction + normalization output, mutable
PlanResolutionDecision  — one human or automatic resolution, persisted for audit
ApprovedMesocycle       — immutable; the only thing a write may derive from
HevyWriteCommand        — individual outbound intent, idempotency-keyed
```

The parser has **no direct write path**. A parser retry can never produce an outbound side effect.

---

## 6. Persistence & Provenance

The parsed plan is **source-of-truth input data** (coach/user authored intent), not a derived analytic. It is therefore exempt from derived-not-stored and *is* persisted.

Retained: raw source file, extraction output, normalized plan, every resolution decision, and the approved revision.

### Non-nullable provenance fields

Enforced at the **schema level**, not merely as a review checklist item — same bar as the Health Connect provenance work:

- `sourceFileHash`
- `parserVersion`
- `rulesetVersion`
- `parsedAtUtc`
- `resolutionDecisionVersion`
- `approvedAtUtc`
- `approvedBy`

This makes it possible to explain why a given routine was generated a particular way, even after the rules have evolved.

---

## 7. Idempotency

PR B–E guarantees idempotent *transport*. PR F still needs its own **intent identity**, or an edited-and-reapproved plan becomes indistinguishable from a retry.

Idempotency key derives from:

```
planId + mesocycleWeek + sessionIndex + approvedRevision
```

`planId` derives deterministically from `sourceFileHash`, so re-ingesting the identical file produces the identical plan identity.

---

## 8. Ambiguity Feedback Loop

**Manual promotion only for v1.**

```
human resolves ambiguity
  → decision persisted as audit data
  → same plan revision reuses that decision
  → user-scoped mapping written to the local override table
  → optional rule-improvement candidate recorded
  → developer reviews and promotes it through a normal PR
```

Automatic promotion is explicitly rejected for v1: one coach-specific synonym or typo could silently become a global alias, and near-identical names can denote materially different movement patterns.

---

## 9. Scope Boundaries

### In scope
- Extraction, normalization, resolution, review, approval, write
- Minimal review UI: list of flagged items, approve/reject, optional free-text note
- Local user-override mapping table

### Out of scope
- Any UI beyond the minimal review screen
- Scheduling *when* workouts occur (Executive / Today layer owns that)
- Health Intelligence, evidence tiers, vault classification
- Retroactive re-parsing of historical plans
- Automatic ruleset mutation

---

## 10. Definition of Done

- [ ] `build_runner` + `flutter analyze` pass
- [ ] Separate unit-test seams for extraction, normalization, resolution, approval, and writing
- [ ] Adversarial malformed-input fixtures (corrupt PDF, merged cells, missing columns, unknown notation)
- [ ] Confidence-policy thresholds tested as fixed conditions, not model output
- [ ] Test proving low-confidence matches never silently write
- [ ] Every write derives from an explicitly approved immutable plan revision
- [ ] Re-ingesting the identical file, or re-approving the same revision, produces zero duplicate Hevy objects
- [ ] Parser has no direct Hevy write path — verified by test, not convention
- [ ] Partial Hevy failure leaves a recoverable state; plan is not marked fully published
- [ ] Provenance fields non-nullable in schema and populated on every parse
- [ ] Ruleset committed, versioned, with changelog section
- [ ] No runtime dependency on an external AI-tool skill directory
- [ ] No regressions to PR B–E Hevy cache/sync tests

---

## 11. Resolved Questions

| Question | Resolution |
|---|---|
| Ruleset in-repo vs. external skill directory | **In-repo**, git-tracked, PR-reviewable, ships with the app |
| Ambiguity decisions auto-promote to ruleset? | **No** — manual promotion only; local override table absorbs user-scoped mappings |
| Who may call the Hevy write path? | **Write executor only**, from an approved immutable plan |

---

## 12. Open Items for Implementation Review

- Whether the YAML machine-readable companion is needed at v1, or markdown-plus-code suffices
- Whether the local override table is user-scoped only, or also plan-scoped (same name meaning different things across two coaches)
- Fuzzy-match threshold value — needs calibration against a real sample of coach plans before locking
