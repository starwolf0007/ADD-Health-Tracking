# PR F: Plan Ingestion — Coach PDF/Excel → Hevy Workout Templates

**Status:** Approved architecture — BLOCKED on PR E (Verified)
**Reviewed by:** Claude, ChatGPT, Grok, Gemini (multi-model convergence, 2026-07)
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

> These paths are the intended homes for the ruleset; the files themselves are authored by the implementation PR, not this architecture-only document. Until then the references are forward-looking targets, not existing files.

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

The write direction **cannot assume idempotent transport.** PR B–E is read-direction only — `HevySyncService.importAll()` performs GETs and idempotent *local* upserts — so it provides no outbound de-duplication. If Hevy accepts a routine-creation request but the response is lost, a naive retry creates a duplicate. PR F therefore owns write-side idempotency itself, in two layers.

**1. Intent identity (local).** Every outbound write carries a deterministic intent key:

```
planId + mesocycleWeek + sessionIndex + approvedRevision
```

`planId` derives deterministically from `sourceFileHash`, so re-ingesting the identical file produces the identical plan identity, and an edited-and-reapproved plan (new `approvedRevision`) is distinguishable from a retry rather than colliding with it.

**2. Remote reconciliation (Hevy-side).** The intent key is also persisted as a stable, machine-readable marker on the created Hevy object (embedded in a reserved namespace within the routine's notes/title), so it can be recovered by read-back. Before creating, the write executor reconciles the intent key against existing Hevy objects:

- **match found** → the write already succeeded; adopt the existing object, create nothing;
- **no match** → create, then record the returned remote object identity locally.

This makes create operations effectively idempotent even though Hevy exposes no transport-level idempotency token. The local key alone is necessary but not sufficient — without the reconciliation step it cannot survive a lost response — so **both** layers are required before the §10 "zero duplicate Hevy objects" guarantee holds.

> Retiring or updating the routine produced by a superseded `approvedRevision` reuses this same remote-object identity; the concrete update/delete/supersession policy is tracked in §12.

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

### Raised in review (2026-07, PR #25) — must be resolved before implementation

These surfaced during PR review and are recorded here rather than silently resolved; each needs a concrete decision in the implementation PR.

- ~~**Write-side idempotency, not just transport.**~~ **Resolved in §7** — the transport-idempotency assumption was corrected and §7 now defines a two-layer contract (local intent identity + Hevy-side read-back reconciliation). The remaining remote-object *supersession* policy is still open (see below).
- **Exercise-template catalog source.** Stage 3 (name → Hevy template ID) has no candidate source for exercises absent from imported history and the canonical aliases; routing to review does not help if the reviewer has no valid template IDs to choose from. Specify how the write boundary fetches, caches, and refreshes the account's available exercise templates before candidate generation.
- **Load-unit normalization.** Hevy stores weight as `weight_kg`; a unitless canonical `load` can silently produce the wrong prescribed weight for lb/mixed/unitless coach files. Normalized loads must carry a source unit + conversion rule, and missing/conflicting units must route through review (§3) rather than auto-resolve.
- **Bind overrides and writes to the connected Hevy account.** Plan/override/write-command identity (§6, §7) carries no Hevy account identifier, so a mapping approved under account A could be reused when writing to account B after an API-key swap. Persist a verified Hevy user ID with overrides, plans, and write commands, and reject or segregate records when the connected account changes.
- **Approval-field placement/nullability.** `approvedAtUtc` / `approvedBy` (§6) cannot be schema-level non-nullable on a draft that is parsed-but-awaiting-review without fabricating approval data. Keep parse-time provenance non-nullable on the draft, but locate the approval-only fields on the `ApprovedMesocycle` record where non-nullability is validly enforceable.
- **Review surface must be able to resolve.** The minimal review UI (§9) currently offers only approve/reject/note; that cannot perform the "human resolves ambiguity" transition (§8) for multi-candidate, unknown-exercise, or unparseable-notation entries. It must also include candidate selection, exercise lookup, and field-correction so an approved plan never admits an unresolved item.

**Second review pass (2026-07, PR #25):**

- **Medical-tier boundary for imported files.** The §1 non-goal exempts this module from vault classification, and §6 retains the raw source file in an ordinary PlanIngestion repository — but a coach PDF can contain injury diagnoses, rehab constraints, or medication notes. `docs/HEALTH_PHASE1_DATA_SPEC.md` (line 46) states medical-tier content is rejected by normal repositories until an isolated encrypted-at-rest vault exists, because device loss is in the threat model. Being a separate input domain does not remove that sensitivity. Define a classification/rejection or redaction boundary before raw files are persisted. *(This one is safety-relevant, not just an implementation detail — it needs an explicit owner decision rather than deferral.)*
- **Domain validation of parsed values.** The §3 gate only routes unsupported notation and parse exceptions to review; values that parse successfully but are impossible or unsafe (negative load, zero sets, negative duration, out-of-range RPE) pass straight through to the write executor. Add deterministic validation for counts, ranges, finiteness, and mutually-compatible set fields, with every violation routed through review.
- **Preserve every prescribed set field through normalization.** §2's normalized syntax carries only sets/reps/load/RPE/superset, but §0 promises set types and rest timers, and the existing `HevySet` model already distinguishes `type`, `distanceMeters`, and `durationSeconds`. Timed/distance sets, warm-up/drop set types, and rest timers must be representable in the normalized form (unsupported/ambiguous values → review) or normalization silently drops prescription detail.
- **Semantic ambiguity in fuzzy matches.** A fixed score threshold does not establish semantic equivalence: after normalization strips punctuation/abbreviations, materially different movements (incline vs. decline, dumbbell vs. barbell) can score above threshold and auto-resolve — which §8 itself warns against. Restrict auto-resolution to exact approved aliases/overrides, or add deterministic movement-attribute guards that send mismatches to review.
- **Supersede published routines after edits.** Including `approvedRevision` in the idempotency identity (§7) deliberately makes a corrected re-approval a *new* write intent, but nothing requires the executor to retire the routine created from the prior revision — so a correction can leave both obsolete and corrected routines in Hevy. Specify a remote-object identity and an update/delete/supersession policy for previously-published revisions.
- **Single executable source for the ruleset.** If the optional YAML (§4) is omitted, canonical policy lives in Markdown while parser behavior lives separately in Dart; either can change without the other, so stored provenance could claim a `rulesetVersion` that does not describe actual parser behavior. Require a bundled machine-readable source, or a checked generation step that produces the runtime representation and verifies it is current.
