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

### Medical-content boundary (mandatory)

Being a separate input domain removes the *evidence/correlation* machinery, **not** the sensitivity of the source file. A coach PDF can carry injury diagnoses, rehabilitation constraints, or medication notes, and `docs/HEALTH_PHASE1_DATA_SPEC.md` requires medical-tier content to stay out of ordinary repositories until an isolated encrypted-at-rest vault exists (device loss is in the threat model).

Therefore, before any raw file is persisted (§6):

1. **Screen the whole file, not just the extracted text.** A deterministic medical-content classifier (keyword/section heuristics versioned with the ruleset) runs over *all* recoverable content. Because scanned pages, embedded images, and non-text objects carry no signal to a text-only classifier, screening requires an **extraction-completeness attestation**: every page/region must be either machine-text-extracted or OCR-inspected. Any file with uninspected content (image-only pages not OCR'd, undecodable objects) **fails the attestation** and is treated as unscreened.
2. **Clean → persist normally.** Only files that pass the attestation with no medical-tier signal follow the normal persistence path.
3. **Flagged or unscreened → do not store the raw file in the PlanIngestion repository.** Redact the medical spans before persisting, or hold the raw bytes only in the isolated encrypted-at-rest vault (once it exists) and persist a redacted derivative plus a `medicalContentRedacted` provenance flag. A file that cannot be fully inspected is withheld the same way — **the boundary fails closed, never open.** The training prescription (sets/reps/load) still flows through the pipeline; only the sensitive raw content is withheld from ordinary storage.

This keeps PlanIngestion consistent with the established health-data doctrine instead of carving a second path around it, and never persists sensitive bytes it did not actually inspect.

---

## 2. Pipeline

Strictly staged. Each stage is independently unit-testable and has its own test seam. Exercise-template lookup **must not** occur inside the raw extractor.

```
source file (PDF/XLSX)
  → 1. structural extraction      (raw text/tables only — deterministic, no interpretation)
  → 2. normalized plan syntax     (sets/reps/unit-tagged load/RPE/set-type/rest/superset in canonical form)
  → 3. resolution candidates      (exercise name → Hevy template ID, with scores)
  → 4. ambiguity review           (human gate; local overrides consulted first)
  → 5. approved immutable plan    (no further mutation permitted)
  → 6. write executor             (sole caller of the Hevy sync layer)
```

### Stage 3/4 resolution order

1. **Local override table** (Drift) — user-confirmed mappings keyed by **coach/plan context**, not just user. An override auto-resolves only within its originating context; the same exercise label from a *different* coach or plan does not silently inherit it and goes to the ambiguity gate instead. This stops one coach's "row" (barbell) from auto-resolving another coach's "row" (machine).
2. **Canonical ruleset** — repo-owned aliases and defaults
3. **Ambiguity gate** — anything unresolved by 1 or 2

### Normalized prescription fields (complete)

The normalized form must carry every prescription detail §0 promises, so approval and writing can reconstruct a fully-specified routine. It is **not** limited to sets/reps/load/RPE/superset:

- **load** — numeric value **plus an explicit unit** (`kg` | `lb` | `bodyweight` | `unitless`); the executor converts to Hevy's `weight_kg`. Missing or mixed/conflicting units are never guessed — they route through review (§3).
- **set type** — `normal` | `warmup` | `drop` | `failure` (maps to `HevySet.type`).
- **timed / distance sets** — `durationSeconds` and `distanceMeters`, mirroring the existing `HevySet` model, for sets not expressed as reps.
- **rest timer** — per-set or per-exercise rest, when the plan specifies it.
- **superset grouping** — unchanged.

Any notation that does not map cleanly onto these fields is unsupported and routes through review rather than being silently dropped.

### Exercise-template catalog

Stage 3 resolves an exercise name to a **Hevy template ID**, which requires a source of valid IDs. Imported workout history (PR B–E) only covers exercises the user has already performed, so it is insufficient alone. The write boundary therefore maintains an **exercise-template catalog** — the account's available Hevy exercise templates — which it fetches, caches locally, and refreshes (staleness-bounded, and on-demand when resolution misses). Stage 3 generates candidates only from this catalog plus the canonical aliases/overrides; an empty or stale catalog for a candidate is a reviewable condition (§3), never a silent failure.

---

## 3. Confidence Policy (deterministic, not model judgment)

The parser may emit scores. The **gate** uses fixed conditions:

| Condition | Outcome |
|---|---|
| Exact normalized alias / user-override match | Auto-resolve |
| Single fuzzy match above threshold **and** movement-attribute guard passes | Auto-resolve |
| Fuzzy match above threshold but movement attributes conflict | **Review required** |
| Multiple plausible candidates | **Review required** |
| Unknown exercise name | **Review required** |
| Unsupported / unparseable notation | **Review required** |
| Set/rep/load parse throws format exception | **Review required** |
| Parsed value out of domain (negative/zero sets, negative load or duration, RPE out of range, non-finite) | **Review required** |
| Missing or conflicting load unit | **Review required** |
| Exercise-template catalog unavailable/stale for the candidate | **Review required** |

Thresholds are configuration, versioned with the ruleset, and covered by tests. A model confidence value alone never authorizes a write.

**Fuzzy matching does not establish semantic equivalence.** A score above threshold is necessary but not sufficient: normalization that strips punctuation/abbreviations can bring materially different movements close (incline vs. decline, dumbbell vs. barbell, machine vs. free-weight). Automatic resolution therefore requires either an *exact* approved alias/override, or a passing **movement-attribute guard** — a deterministic comparison of equipment, angle/orientation, and unilateral/bilateral attributes between the parsed name and the candidate. Any attribute conflict forces review regardless of score.

**Domain validation runs before the gate.** Successfully-parsed values are checked for sane counts, ranges, finiteness, and mutually-compatible set fields (e.g. a set cannot be both rep-based and duration-based without an explicit type). Violations route through review — a value that *parses* is not yet a value that may be *written*.

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

**Approval and command creation are atomic.** Persisting an `ApprovedMesocycle` and inserting all of its derived `HevyWriteCommand` records happen in **one transaction**, so approval can never leave an approved-but-unpublishable plan with no outbound work for the executor to recover. As a backstop, a deterministic recovery scan materializes missing commands for any approved plan that has none — commands derive deterministically from the immutable approved revision, so re-materialization is safe and idempotent.

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
- `hevyAccountId`

This makes it possible to explain why a given routine was generated a particular way, even after the rules have evolved.

### Account binding

Overrides, plans, and write commands are **scoped to a verified Hevy account.** On connect, the `GET /user/info` result is retained as a stable `hevyAccountId` (not discarded), and that ID is stored on the local override table, each `ApprovedMesocycle`, and every `HevyWriteCommand`, and enforced on the write path so a mapping approved under account A can never be resolved against or written to account B. When the connected account changes (API-key swap), records from the previous account are segregated — neither resolved against nor written — until re-confirmed under the new account.

---

## 7. Idempotency

The write direction **cannot assume idempotent transport.** PR B–E is read-direction only — `HevySyncService.importAll()` performs GETs and idempotent *local* upserts — so it provides no outbound de-duplication. If Hevy accepts a routine-creation request but the response is lost, a naive retry creates a duplicate. PR F therefore owns write-side idempotency itself, in two layers.

**1. Intent identity (local).** Every outbound write carries a deterministic intent key:

```
planId + mesocycleWeek + sessionIndex + approvedRevision
```

`planId` is a **stable logical plan identity**, assigned once when a plan is first ingested — **not** derived from the file bytes. A corrected source file is ingested as a new *revision of the same `planId`* through an explicit `replaces` relationship (chosen at ingest: "new plan" vs. "correction of plan X"), so a fixed typo does not fork into a second plan. `sourceFileHash` is retained as **provenance only**, and additionally used to dedup *identical* re-ingests (same bytes → same revision — a retry, not a new revision). Because `planId` is stable across corrected files, the supersession lookup below reliably finds the previously-published routine instead of stranding it as a duplicate.

**2. Remote reconciliation (Hevy-side).** The intent key is also persisted as a stable, machine-readable marker on the created Hevy object (embedded in a reserved namespace within the routine's notes/title), so it can be recovered by read-back. Before creating, the write executor reconciles the intent key against existing Hevy objects:

- **match found** → the write already succeeded; adopt the existing object, create nothing;
- **no match** → create, then record the returned remote object identity locally.

This makes create operations effectively idempotent even though Hevy exposes no transport-level idempotency token. The local key alone is necessary but not sufficient — without the reconciliation step it cannot survive a lost response — so **both** layers are required before the §10 "zero duplicate Hevy objects" guarantee holds.

### Serialized, single-owner execution

The reconcile-then-create in layer 2 is **not atomic by itself**: two concurrent runners (e.g. a foreground action and a background retry) could both read "no match" and both create. Execution is therefore serialized on the **session slot** — `hevyAccountId + planId + mesocycleWeek + sessionIndex` — **not** the revision-specific intent key. This matters because two *different* revisions of one session (N and N+1) carry different intent keys and would otherwise take independent leases and both create; leasing by the slot forces them into a single ordered publisher. The slot lease is a state machine — `pending → leased → published` (or `failed`) — and **only the current lease holder may create or supersede**; any other runner for the same slot (a retry, a background pass, or a newer revision) observes the active lease and waits or no-ops. Leases expire, and on expiry/restart recovery re-runs reconciliation by the remote marker *before* re-leasing, so a create that succeeded but whose response or local record was lost is adopted, not duplicated. The stable `planId`, the remote marker, and the slot lease together back the §10 zero-duplicate guarantee.

### Superseding a published revision

Because `approvedRevision` is part of the intent identity, re-approving a corrected plan is a *new* write intent, not a retry — so without a supersession rule both the old and corrected routines would coexist in Hevy. On publishing revision *N+1* for a `(planId, mesocycleWeek, sessionIndex)` that already has a published revision *N*, the executor:

1. resolves revision *N*'s recorded remote-object identity (layer 2 above);
2. **updates that object in place** to the *N+1* content when Hevy supports update, or **deletes *N* then creates *N+1*** otherwise;
3. marks revision *N* superseded locally only after Hevy confirms.

A partial failure leaves the plan *not* marked fully published (§10) and is recoverable on retry, since the intent key + remote identity still resolve. Exactly one live routine per `(planId, week, session)` is the invariant.

---

## 8. Ambiguity Feedback Loop

**Manual promotion only for v1.**

```
human resolves ambiguity
  → decision persisted as audit data
  → same plan revision reuses that decision
  → context-scoped mapping (coach/plan) written to the local override table
  → optional rule-improvement candidate recorded
  → developer reviews and promotes it through a normal PR
```

Automatic promotion is explicitly rejected for v1: one coach-specific synonym or typo could silently become a global alias, and near-identical names can denote materially different movement patterns.

---

## 9. Scope Boundaries

### In scope
- Extraction, normalization, resolution, review, approval, write
- Review UI capable of *resolving* every flagged item, not merely listing it: candidate selection from the exercise-template catalog, exercise lookup/search for unknown names, and field-correction for normalized values (load + unit, sets/reps, set type, timed/distance, rest), plus approve/reject and an optional free-text note. Approval is blocked while any item remains unresolved.
- Local user-override mapping table

### Out of scope
- Any UI beyond the review screen defined above
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
- [ ] Loads carry an explicit unit; missing/conflicting units route through review and never auto-convert
- [ ] Set type, timed/distance, and rest-timer fields survive normalization or route through review
- [ ] Impossible-but-parseable values (negative/zero, out-of-range RPE, non-finite) are caught by domain validation, not written
- [ ] Fuzzy matches with conflicting movement attributes route through review; only exact aliases/overrides or attribute-guarded matches auto-resolve
- [ ] Exercise-template catalog is fetched/cached/refreshed; resolution draws candidates only from it plus aliases/overrides
- [ ] Overrides, plans, and write commands are bound to a verified `hevyAccountId`; account switch segregates prior records
- [ ] Approval + all derived write commands persist in one transaction (or a recovery scan re-materializes missing commands)
- [ ] Concurrent/retried writes cannot duplicate — publication serialized by a lease on the session slot (account + planId + week + session), across revisions
- [ ] `planId` is a stable logical identity; a corrected source file supersedes the prior routine instead of creating a second — exactly one live routine per (planId, week, session)
- [ ] Overrides auto-resolve only within their originating coach/plan context; cross-context reuse routes through review
- [ ] Raw files fully inspected (text + OCR attestation) before persistence; flagged or un-inspectable content redacted or withheld — boundary fails closed
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
- Fuzzy-match threshold value — needs calibration against a real sample of coach plans before locking

*(The earlier "user-scoped vs. plan-scoped override table" question is now resolved — overrides are keyed by coach/plan context; see §2.)*

### Raised in review (2026-07, PR #25)

**All P1 findings resolved in-body** (see the referenced sections):

| Finding | Resolved in |
|---|---|
| Write-side idempotency (transport not guaranteed) | §7 — two-layer contract |
| Concurrent/retried create race (non-atomic check-then-create) | §7 — leased single-owner execution |
| Cross-revision publication race (per-revision leases don't serialize) | §7 — lease on the session slot (account + planId + week + session) |
| Supersede published routines after edits | §7 — supersession policy |
| Stable plan ID across corrected source files | §7 — logical `planId`, `sourceFileHash` demoted to provenance |
| Atomic approval → command handoff | §5 — one transaction + recovery scan |
| Exercise-template catalog source | §2 — exercise-template catalog |
| Load-unit normalization → `weight_kg` | §2 fields + §3 gate |
| Preserve set type / timed / distance / rest | §2 — normalized prescription fields |
| Domain validation of impossible parsed values | §3 — gate + pre-gate validation |
| Semantic ambiguity in fuzzy matches | §3 — movement-attribute guard |
| Override scoped to coach/plan context (no cross-coach bleed) | §2 — context-keyed override table |
| Bind overrides/writes to the connected Hevy account | §6 — account binding |
| Review surface must be able to resolve flagged items | §9 — resolving review UI |
| Medical-tier boundary + full-file screening attestation | §1 — screen whole file (text + OCR), fail closed |

**Still open — P2, deferred to the implementation PR (do not gate safety, but track):**

- **Approval-field placement/nullability.** `approvedAtUtc` / `approvedBy` (§6) cannot be schema-level non-nullable on a parsed-but-unapproved draft without fabricating approval data. Keep parse-time provenance non-nullable on the draft, but locate the approval-only fields on the `ApprovedMesocycle` record where non-nullability is validly enforceable.
- **Single executable source for the ruleset.** If the optional YAML (§4) is omitted, canonical policy lives in Markdown while parser behavior lives in Dart; either can drift, so stored provenance could claim a `rulesetVersion` that doesn't describe actual behavior. Require a bundled machine-readable source, or a checked generation step that verifies the runtime representation is current.
- **End-to-end golden tests.** Stage-seam and malformed-input tests cannot catch a field dropped or miswired *at a stage boundary*. Add golden fixtures that take representative valid PDF and XLSX plans through the full pipeline and assert the exact resulting routine (ordering, units, set types, supersets, rest timers).
- **Bounded resource use for imported documents.** A very large PDF or a decompression-bomb XLSX can exhaust mobile memory/storage. Define byte, decompressed-size, page, row/cell, and processing-time limits with rejection tests, so adversarial documents cannot cause a local denial of service.

> **Status note:** the header remains "Approved architecture — BLOCKED on PR E." With the P1 items above resolved in-body, the only remaining open items are P2 hardening/testing concerns that belong to the implementation PR and do not represent unsafe unresolved decisions.
