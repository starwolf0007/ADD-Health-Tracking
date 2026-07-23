# Multi-AI Validation Prompt — Health Connect Steps Slice

You are reviewing NeuroFlow's proposed Health Connect Steps vertical slice.
Treat this as an architecture and implementation review, not a writing exercise.

## Repository and branch

- Repository: `starwolf0007/ADD-Health-Tracking`
- Review branch: `review/health-connect-steps-draft`
- Parent branch: `feature/health-connect-adapter`
- Related PR: #22

## Required context

Read these files before giving conclusions:

- `docs/reference/README.md`
- `docs/reference/reference-matrix.md`
- `docs/reference/template.md`
- `docs/reference/architecture/google-health-connect.md`
- `lib/domain/health/health_enums.dart`
- `lib/domain/health/health_transaction.dart`
- `lib/health/data/health_write_guard.dart`
- the current `HealthConnectBridge.kt` on the parent branch

## Locked doctrine

1. Health Connect is a sensor bus, not NeuroFlow's domain model.
2. Ingestion preserves raw source evidence.
3. One upstream `StepsRecord` produces one `HealthTransaction`.
4. Overlapping watch and phone records remain separate.
5. No aggregation, deduplication, preferred-provider selection, or interval merging occurs during ingestion.
6. Kotlin returns plain transport values only; Android SDK objects do not cross the MethodChannel.
7. Dart performs strict parsing and canonical mapping.
8. Existing `generateHealthEvidenceId()` and existing domain contracts must be reused.
9. Every produced transaction must pass `requirePhase1Transaction()`.
10. Drift persistence, change tokens, WorkManager, background sync, UI, and other record types are outside this slice.

## Proposed Commit B scope

Validate a design containing:

- bounded `readRecords<StepsRecord>()` Kotlin reader
- one transport map per native record
- stable wire keys and primitive values
- source package, timestamps, offsets, last-modified metadata, client metadata, recording method, and count
- lifecycle-safe MethodChannel result handling
- strict Dart parser with safe reason codes
- one `HealthSourceRecordDraft` and one `HealthSpanDraft` per record
- one `HealthTransaction` per record
- deterministic identity generated in Dart
- overlap, malformed-payload, deterministic-ID, and repository-guard tests

## Questions you must answer

### Architecture

- Does this preserve the existing one-source-record transaction invariant?
- Does any proposed layer accidentally aggregate, flatten, or reinterpret evidence?
- Are responsibilities correctly divided among Kotlin transport, Dart parsing, domain mapping, repository validation, and later derived analytics?
- Is any new abstraction redundant with an existing repository contract?

### Health Connect correctness

- Verify the pinned `connect-client:1.1.0` APIs and exact metadata/recording-method constants.
- Verify whether bounded `readRecords` paging is required and how the page token should be handled.
- Verify interval-boundary semantics and whether the proposed naming `startInclusive` / `endExclusive` is accurate.
- Verify all transported field types across Kotlin and Flutter MethodChannel serialization.

### Lifecycle and failure behavior

- Could engine or activity detachment strand a pending Dart Future?
- Could any result receive a duplicate or late reply?
- Is returning an empty list for native failure sufficiently distinguishable from a valid empty read, or should the wire contract expose a closed status without leaking exception details?
- Are cancellation and coroutine ownership correct?

### Dart/domain correctness

- Does mapping use the real constructors and enum names in the branch?
- Is `transactionId` identity correct and stable across repeated ingestion runs?
- Is the source-record ID distinct from span evidence ID for a clear reason?
- Is local-date derivation correct when offsets are null or differ between start and end?
- Should malformed records be individually rejected while valid siblings continue?
- Are rejection reason codes safe to log and free of health values and external identifiers?

### Tests

Require tests proving:

- two overlapping origins produce two transactions and two spans
- no counts are summed
- IDs differ across distinct origins/records
- the same upstream record yields stable IDs across runs
- malformed provenance, counts, ranges, timestamps, map keys, and offsets are rejected
- valid siblings survive a malformed record
- null offsets remain null
- engine detachment completes pending reads exactly once
- every valid transaction passes `requirePhase1Transaction()`

## Output format

Respond in this exact structure:

### Verdict
`APPROVE`, `APPROVE WITH CHANGES`, or `REJECT`

### Blocking findings
Numbered findings that must be fixed before implementation or merge. Include exact file/class/function references.

### Non-blocking improvements
Only changes that improve clarity, maintainability, or test coverage without changing correctness.

### Verified API facts
List each Health Connect or Flutter API fact you independently verified, with canonical source links and version relevance.

### Recommended final file plan
Give exact repository paths and state whether each file is new or modified.

### Minimum test matrix
Provide test names and the invariant each protects.

### Doctrine conflicts
State `None` or quote the exact doctrine line that the proposal violates.

Do not redesign unrelated parts of NeuroFlow. Do not introduce persistence,
background synchronization, additional health types, analytics, or UI into this
slice. Clearly label assumptions and do not claim verification without checking
canonical sources or the actual branch files.
