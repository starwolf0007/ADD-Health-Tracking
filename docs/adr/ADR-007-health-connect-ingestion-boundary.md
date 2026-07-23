# ADR-007: Health Connect ingestion boundary

**Status:** Accepted  
**Date:** 2026-07-23

## Context

Health Connect exposes Android SDK record types, metadata constants, permissions,
and provider-specific provenance. NeuroFlow needs those records as evidence, but
must not allow Android SDK types, aggregation behavior, or source-selection logic
to define its domain model.

Steps are the first vertical slice. Multiple providers may report overlapping
intervals for the same person. Flattening or summing those records during
transport would destroy provenance and make later reconciliation impossible.

## Decision

- Health Connect is treated as a sensor bus and platform transport layer, not as NeuroFlow's domain model.
- Kotlin reads Health Connect records and emits plain MethodChannel primitives only.
- Android SDK objects and raw recording-method integer constants do not cross the platform boundary.
- Dart owns strict parsing, normalization, deterministic identity, and construction of existing health-domain contracts.
- Each upstream `StepsRecord` produces exactly one `HealthSourceRecordDraft`, one `HealthSpanDraft`, and one `HealthTransaction`.
- Overlapping records from different origins remain independent evidence.
- Ingestion never merges intervals, sums counts, deduplicates records, chooses a preferred provider, or creates daily totals.
- Deterministic IDs are generated with the existing `generateHealthEvidenceId()` function.
- For the Steps slice, `transactionId` may equal the source-record ID. This shortcut is not automatically applicable to future series-based record types and must be reviewed per type.
- Every produced transaction must pass `HealthWriteGuard.requirePhase1Transaction()` before persistence is considered.
- The MethodChannel uses the frozen `HealthConnect Steps Transport v1` closed result envelope documented in `docs/reference/architecture/google-health-connect.md`.
- Native failures map to a closed status (`unavailable`, `permission_denied`, or `failed`) with an always-present records list and no native exception details.
- Recording methods cross the wire as `automatic`, `active`, `manual`, or `unknown`. Dart maps both automatic and active records to `RecordingMethod.deviceMeasured`.

## Alternatives Considered

- Use Health Connect `aggregate()` for Steps, as Google's raw-read guidance recommends for cumulative records to avoid multi-source double counting — deliberately rejected for NeuroFlow's evidence-ingestion boundary because aggregation discards the independent source records and provenance required for later reconciliation. Aggregation remains appropriate only as a downstream derived operation.
- Aggregate Steps totals in Kotlin — rejected because source-level evidence and provenance would be unrecoverable.
- Transport Android SDK objects or raw constants — rejected because it couples the Dart domain to Android implementation details.
- Build a parallel Health Connect DTO/domain hierarchy — rejected because existing `HealthSourceRecordDraft`, `HealthSpanDraft`, and `HealthTransaction` contracts already define the canonical boundary.
- Return an empty list for both success and native failure — rejected because a genuine zero-record read must remain distinguishable from a failed read.
- Map actively recorded data to `sourceEstimated` — rejected because active recording is still a direct device measurement, not an estimate.

## Consequences

- Source provenance remains immutable and available for later reconciliation and derived analytics.
- Kotlin and Dart share a small, versioned internal wire contract.
- Future transport changes that rename, remove, repurpose, or overload fields require a transport-version increment.
- The adapter needs strict malformed-record rejection and partial-batch handling so one invalid record does not discard valid siblings.
- Paging, interval boundaries, recording-method constants, and lifecycle behavior must be verified against the pinned Health Connect SDK before production code lands.
- Persistence, incremental change tokens, background sync, UI, and additional health types remain separate work.

## Related Documents

- [Google Health Connect reference audit](../reference/architecture/google-health-connect.md)
- [Health Connect Steps validation prompt](../review/health-connect-steps-validation-prompt.md)
- [ADR-006](ADR-006-intelligence-is-optional.md)
- `lib/domain/health/health_transaction.dart`
- `lib/health/data/health_write_guard.dart`
