# NeuroFlow Health Intelligence — Phase 1 Data Specification

**Status:** Canonical implementation baseline  
**Governing doctrine:** Approved Health Intelligence Doctrine  
**Scope:** Local evidence ingestion and trust UI only. No causal explanations, hypothesis graph, Body Age, medical vault, Home Assistant, cloud synchronization, or Lexi access to raw health data.

## 1. Purpose and architectural placement

NeuroFlow Health is an n-of-1 learning system built on user-owned evidence. Phase 1 establishes trustworthy capture, provenance, ownership, and data-quality visibility before NeuroFlow is allowed to interpret health evidence.

Health Intelligence is a domain module parallel to the Executive Engine. It uses repositories over Drift tables. The Executive Engine and Lexi may not read raw health repositories.

```text
Presentation
├── Executive UI
├── Health trust / coverage UI
└── Lexi (approved view models only)

Domain
├── Executive Engine
└── Health Intelligence
    ├── ingestion
    ├── normalization
    ├── deduplication
    └── coverage

Data
├── existing NeuroFlow tables
└── health evidence tables

Platform
└── Health Connect adapters and Android permissions
```

## 2. Locked storage and security decisions

- Drift / SQLite on the Pixel is the Phase 1 authority.
- Health Connect and vendor APIs are ingestion buses, never masters.
- Raw source evidence is immutable or append-only.
- Normalized evidence can be rebuilt from retained source evidence.
- Missing observations are never converted to zero.
- NeuroFlow-derived or imputed values do not enter Phase 1 evidence tables.
- Every external-facing record has a stable NeuroFlow text identifier in addition to any internal SQLite row id.
- Lexi receives no raw time-series, source payloads, medical documents, or unrestricted graph state.
- Routine and sensitive health data remain local-first. Sensitive export requires explicit confirmation and production export should support encryption.
- Medical-tier content is rejected by Phase 1 repositories. The future medical vault must use isolated encrypted-at-rest storage because device loss is part of the threat model even without a backend.

## 3. Source records separated from normalized evidence

A near-raw `health_source_records` table sits above the normalized evidence shapes. One source record may produce multiple normalized facts without duplicating the raw payload.

Example:

```text
Health Connect sleep record
          ↓
health_source_records
          ↓
sleep session span
sleep-stage spans
sleep summary events
```

### `health_source_records`

- `source_record_id` TEXT PK — NeuroFlow UUID / ULID
- `source_id` TEXT FK
- `source_app_id` TEXT nullable — Android package or vendor origin
- `device_id` TEXT nullable FK
- `external_id` TEXT nullable — source record identifier
- `source_record_type` TEXT
- `started_at_utc` INTEGER
- `ended_at_utc` INTEGER nullable
- `start_offset_seconds` INTEGER nullable
- `end_offset_seconds` INTEGER nullable
- `local_date` TEXT
- `source_modified_at_utc` INTEGER nullable
- `raw_payload_json` TEXT nullable
- `raw_payload_hash` TEXT nullable
- `sensitivity_class` INTEGER
- `consent_scope` TEXT nullable
- `ingested_at_utc` INTEGER
- `last_processed_at_utc` INTEGER
- `normalization_schema_version` INTEGER
- `normalizer_version` TEXT
- `deleted_at_utc` INTEGER nullable
- `supersedes_source_record_id` TEXT nullable

```sql
CREATE UNIQUE INDEX idx_health_source_record_external
ON health_source_records(source_id, source_app_id, external_id)
WHERE external_id IS NOT NULL;
```

## 4. Domain classifications

Recording origin, availability, and quality are separate concepts.

```dart
enum SensitivityClass {
  routine,
  sensitive,
  medical,
}

enum MeasurementStatus {
  valid,
  partial,
  unavailable,
  invalid,
  deleted,
}

enum RecordingMethod {
  deviceMeasured,
  userEntered,
  sourceEstimated,
  sourceDerived,
  importedUnknown,
}

enum QualityLabel {
  unknown,
  low,
  moderate,
  high,
}
```

`imputed` and `neuroFlowDerived` are intentionally absent. They belong in later rebuildable analytical-artifact tables.

A generic numeric confidence score is not canonical unless its calculation is explicitly defined. Use `QualityLabel`, source quality metadata, and mathematically defined completeness ratios.

## 5. Normalized evidence shapes

The three-shape design avoids nullable-column chaos and keeps high-frequency SQLite queries efficient.

### `health_events`

Point-in-time normalized evidence, including weigh-ins, nutrition intake, blood-pressure readings, medication events, and other discrete facts.

Required fields:

- internal integer `row_id`
- stable text `evidence_id`
- nullable `source_record_id` FK
- controlled `concept_type`
- `event_timestamp_utc`
- nullable `timezone_offset_seconds`
- `local_date`
- nullable numeric / text / boolean values
- nullable canonical unit
- nullable normalized payload JSON
- measurement status, recording method, quality label, sensitivity
- nullable completeness ratio
- validation and normalization warnings
- normalization schema and normalizer versions
- tombstone / supersession fields

### `health_spans`

Duration evidence, including sleep sessions, sleep stages, workouts, walking intervals, meditation, and fasting windows.

Required fields mirror events plus:

- `start_timestamp_utc`
- `end_timestamp_utc`
- separate start and end offsets
- `duration_seconds`
- nullable parent span id
- nullable summary value / summary JSON

Database constraints must reject end-before-start and completeness outside 0.0–1.0.

### `health_series`

Container-level provenance for high-frequency records such as a Health Connect heart-rate series.

Contains:

- source-record and device linkage
- interval boundaries and offsets
- sample count and optional expected sample count
- completeness and quality
- raw payload only once at source-record or series level

### `health_time_series`

Lean sample rows:

- internal integer row id
- stable evidence id
- series id FK
- concept type
- timestamp UTC and nullable offset
- local date
- numeric value and canonical unit
- optional sequence number
- measurement status, recording method, quality, sensitivity
- validation flags and normalization version

Synthetic rows must never be generated merely to represent a missing sample. Missingness is represented through observation gaps, source-reported unavailable states, series completeness, and coverage summaries.

## 6. First-class contextual events

Phase 1 includes minimal manual context capture because later analysis needs context unavailable from sensors.

Context uses the same evidence and provenance rules but receives a dedicated table or repository contract, `health_context_events`, to avoid mixing user narrative with high-volume measurement queries.

Starter controlled types:

- `context.illness`
- `context.alcohol`
- `context.high_stress`
- `context.travel`
- `context.late_meal`
- `context.medication_taken`
- `context.watch_removed`
- `context.unusual_schedule`

Required fields:

- stable id
- start and optional end time
- local offsets and date
- optional intensity: unknown / low / moderate / high
- optional short note
- manual source and user-entered recording method
- sensitivity class
- created and modified timestamps

The capture UI must remain optional, low-friction, and tolerant of incomplete entries.

## 7. Controlled concept registry and canonical units

Concept types are stored as text for extensibility but may only be written through a code-controlled registry. Adapters cannot invent strings.

Starter concepts include:

- `body.weight`
- `body.fat_percentage`
- `body.lean_mass`
- `cardiovascular.heart_rate`
- `cardiovascular.resting_heart_rate`
- `cardiovascular.hrv_rmssd`
- `cardiovascular.blood_pressure_systolic`
- `cardiovascular.blood_pressure_diastolic`
- `sleep.session`
- `sleep.stage.awake`
- `sleep.stage.light`
- `sleep.stage.deep`
- `sleep.stage.rem`
- `activity.workout`
- `activity.steps`
- `activity.active_energy`
- `nutrition.meal`
- `nutrition.energy`
- `nutrition.protein`
- `nutrition.carbohydrate`
- `nutrition.fat`
- `nutrition.caffeine`
- `nutrition.alcohol`
- `nutrition.water`

Canonical unit conversion belongs in versioned deterministic Dart code, not a user-editable database table. Source units remain in retained source metadata or raw payloads.

## 8. Coverage cache

Adopt `health_data_coverage` as a rebuildable materialized cache, never ground truth.

- id
- concept type
- window start / end UTC
- expected periods or samples
- observed periods or samples
- valid periods or samples
- coverage ratio
- quality label
- calculation version
- calculated timestamp

This powers trust statements such as: “Sleep duration is available for 27 of the last 30 nights.”

No analytics feature may assume complete data without checking an applicable coverage artifact.

## 9. Provenance, updates, deduplication, and deletion

Deduplication order:

1. Stable source identity: source + source app + external id.
2. Compare source modification timestamp and raw payload hash.
3. Use a metric-specific fallback fingerprint only when no stable id exists.
4. Never automatically collapse similar records from different origins.
5. Never average presumed duplicates.

Source updates create a new immutable source-record version or supersede prior normalized evidence according to the adapter contract. Imported evidence remains auditable.

A dedicated `deduplication_log` is not required in Phase 1. Ingestion-run counters, source identity, supersession links, tombstones, and optional record-link rows provide the audit trail.

### Deletion and future dependency invalidation

- A source deletion creates a tombstone and marks or supersedes affected normalized evidence according to retention policy.
- Deleting or withdrawing consent for source evidence must remove it from active coverage calculations and exports.
- Phase 1 has no hypothesis graph, but deletion events must be emitted through a repository-level invalidation contract.
- Future analytical artifacts and hypothesis edges must record their source evidence identifiers.
- When source evidence is deleted, corrected, or consent is withdrawn, dependent analytical artifacts must be invalidated and recomputed or retired. They may never remain active silently.
- User deletion must not be defeated by append-only audit design. Minimal tombstone metadata may remain only when required to prevent accidental re-import, and must not preserve deleted health values.

## 10. Required support tables

- `health_sources`
- `health_devices`
- `health_source_records`
- `health_events`
- `health_spans`
- `health_series`
- `health_time_series`
- `health_context_events`
- `health_data_coverage`
- `health_ingestion_runs`
- `health_ingestion_checkpoints`
- `health_tombstones`
- `health_permissions`

Each checkpoint is scoped by source and Health Connect record type. Checkpoints advance only inside the same successful transaction that writes the corresponding evidence.

## 11. Index baseline

Required indexes include:

- events: `(concept_type, event_timestamp_utc)`
- spans: `(concept_type, start_timestamp_utc)` and end timestamp
- series: `(concept_type, start_timestamp_utc)`
- samples: `(concept_type, timestamp_utc)`
- samples: `(series_id, timestamp_utc)`
- context: `(event_type, start_timestamp_utc)`
- local-day paths: `(concept_type, local_date)` where used
- unique source-record identity partial indexes
- source-record linkage indexes on normalized evidence

Additional indexes require measured query-plan evidence rather than speculation.

## 12. Export and ownership

Phase 1 provides user-controlled export of:

- source registry
- normalized evidence
- provenance
- coverage summaries
- optionally retained raw payloads

Sensitive export requires explicit confirmation. Production-sensitive exports should support encrypted output. Medical-class export remains out of scope until the isolated vault exists.

Exports must distinguish active, superseded, invalid, and deleted evidence. Deleted health values must not leak into normal exports.

## 13. Phase 1 exclusions

Do not add:

- hypothesis or knowledge graph tables
- effect estimates or confidence intervals
- evidence-tier analytical results
- Body Age or composite scores
- medical document storage
- Home Assistant entities
- cloud synchronization tables
- raw-data access for Lexi
- model inference or causal-language generation

The evidence-tier language envelope is part of the governing doctrine, but a production LLM validator is not required until an insight-generation path exists. Phase 1 should define deterministic evidence-tier enums and template contracts so the safeguard is not retrofitted later.

## 14. Definition of done

Phase 1 is not verified until:

- `dart run build_runner build --delete-conflicting-outputs` succeeds
- `flutter analyze` succeeds
- the full automated test suite succeeds
- schema snapshot and migration tests cover the existing database upgrade to the health schema version
- repeated ingestion is idempotent
- source updates and deletions reconcile correctly
- missing data is never coerced to zero or interpreted as a negative event
- no ingestion code assumes complete coverage
- timezone, DST, revoked-permission, interrupted-transaction, and malformed-record tests pass
- repositories prevent Presentation, Executive, and Lexi from reading raw Drift health tables directly
- diagnostic logs redact health values and raw payloads

## 15. First vertical slice

Import through Health Connect:

1. one Withings weight source record normalized into a health event
2. one Pixel Watch heart-rate source series normalized into a series and samples
3. one sleep source record normalized into a sleep span

Then verify:

- repeated synchronization is idempotent
- source app and device provenance are retained
- UTC, local offsets, and local dates are correct
- canonical units are deterministic
- raw payload is retained once where permitted
- source updates supersede correctly
- deletions create tombstones and emit invalidation events
- revoked permissions do not delete already imported evidence
- coverage UI reports missing and partial data honestly

## 16. Implementation order

1. Add enums and controlled concept registry.
2. Add source, device, source-record, evidence-shape, ingestion, permission, tombstone, and coverage tables.
3. Increment the existing `AppDatabase` schema version from 6 to 7 and implement a forward-only migration.
4. Add schema snapshots and migration tests before introducing another schema version.
5. Build repository boundaries; Presentation never reads Drift tables directly.
6. Define the evidence invalidation event contract used now for deletion and later by analytical artifacts.
7. Build the narrow Health Connect adapter slice.
8. Add trust / coverage UI and minimal context capture.
9. Add explicit user export.

This specification is conservative by design. Phase 1 proves trustworthy capture, ownership, provenance, deletion behavior, and security boundaries before NeuroFlow is allowed to interpret health evidence.
