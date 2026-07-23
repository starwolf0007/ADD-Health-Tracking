# Multi-AI Validation Prompt — Health Connect Steps Slice

You are reviewing NeuroFlow's proposed Health Connect Steps vertical slice.
Treat this as an implementation-fact validation, not an invitation to reopen
settled architecture.

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
- `docs/adr/ADR-007-health-connect-ingestion-boundary.md`
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
6. Kotlin returns plain transport values only; Android SDK objects and integer constants do not cross the MethodChannel.
7. Dart performs strict parsing and canonical mapping.
8. Existing `generateHealthEvidenceId()` and existing domain contracts must be reused.
9. Every produced transaction must pass `HealthWriteGuard.requirePhase1Transaction()`.
10. Drift persistence, change tokens, WorkManager, background sync, UI, and other record types are outside this slice.
11. The Steps v1 wire contract is frozen; incompatible changes require a transport-version increment.

## Frozen HealthConnect Steps Transport v1

```yaml
status: "ok" | "unavailable" | "permission_denied" | "failed"
records:
  - externalId: String
    recordType: "steps"
    count: Long
    startEpochMs: Long
    endEpochMs: Long
    startZoneOffsetSeconds: Int?
    endZoneOffsetSeconds: Int?
    sourceAppId: String
    lastModifiedEpochMs: Long
    clientRecordId: String?
    clientRecordVersion: Long?
    recordingMethod: "automatic" | "active" | "manual" | "unknown"
```

Contract rules:

- `records` is always present and is always a list.
- `ok` plus an empty list is a successful zero-record read.
- Other statuses return an empty records list.
- Unknown statuses fail closed as `failed` in Dart.
- Native exception text, stack traces, and class names do not cross the channel.
- Missing or blank `sourceAppId` is malformed provenance; it does not default to a fabricated source.
- Kotlin translates Android recording-method constants into the four stable strings.
- Dart maps `automatic` and `active` to `deviceMeasured`, `manual` to `userEntered`, and `unknown` to `importedUnknown`.
- No field may be renamed, removed, repurposed, or overloaded without incrementing the transport version.

## Proposed Commit B scope

Validate a design containing:

- bounded and fully paged `readRecords<StepsRecord>()` Kotlin reader
- one transport map per native record
- the closed result envelope above
- source package, timestamps, offsets, last-modified metadata, client metadata, recording method, and count
- lifecycle-safe MethodChannel result handling inside the existing `HealthConnectBridge.kt`
- strict Dart parser with safe reason codes
- one `HealthSourceRecordDraft` and one `HealthSpanDraft` per record
- one `HealthTransaction` per record
- deterministic identity generated in Dart with `generateHealthEvidenceId()`
- an explicit mapper comment that `transactionId == sourceRecordId` is a Steps-slice decision, not a universal series-record rule
- overlap, malformed-payload, deterministic-ID, result-envelope, and repository-guard tests

## Questions you must answer

### Architecture conformance

- Does this preserve the existing one-source-record transaction invariant?
- Does any proposed layer accidentally aggregate, flatten, or reinterpret evidence?
- Does the implementation reuse the real constructors, enum names, identity function, and static write guard from the branch?
- Is any new abstraction redundant with an existing repository contract?

### Health Connect 1.1.0 correctness

- Verify the pinned `connect-client:1.1.0` APIs and exact recording-method constants.
- Verify the exact constant-to-wire-string mapping; do not infer it from names alone.
- Verify bounded `readRecords` paging behavior and the exact page-token loop.
- Verify interval-boundary semantics and recommend accurate Kotlin/Dart argument names.
- Verify all transported field types across Kotlin and Flutter MethodChannel serialization.
- Verify `Metadata.id`, `DataOrigin.packageName`, last-modified time, client record metadata, and zone-offset availability for `StepsRecord`.

### Lifecycle and failure behavior

- Does the Steps method mirror the existing permission-result ownership pattern?
- Could engine or activity detachment strand a pending Dart Future?
- Could any result receive a duplicate or late reply?
- Does every native outcome produce exactly one closed result envelope?
- Are permission revocation, platform unavailability, security exceptions, and unexpected read failures mapped to the correct closed status without leaking details?
- Are cancellation and coroutine ownership correct?

### Dart/domain correctness

- Does the parser distinguish successful empty reads from failures?
- Does an unknown or malformed status fail closed?
- Is `transactionId` identity correct and stable across repeated ingestion runs?
- Is the source-record ID distinct from span evidence ID for a clear reason?
- Is local-date derivation deterministic when offsets are null or differ between start and end?
- Are malformed records individually rejected while valid siblings continue?
- Are rejection reason codes safe to log and free of health values and external identifiers?
- Are both `automatic` and `active` correctly classified as `deviceMeasured` rather than `sourceEstimated`?

### Tests

Require tests proving:

- two overlapping origins produce two transactions and two spans
- no counts are summed
- IDs differ across distinct origins/records
- the same upstream record yields stable IDs across runs
- missing external ID, blank provenance, negative count, invalid timestamps, reversed ranges, malformed map entries, invalid offsets, and unknown keys are handled according to the strict parser contract
- valid siblings survive a malformed record
- null offsets remain null and differing start/end offsets are preserved independently
- `ok` plus empty records remains distinguishable from `failed`
- unknown statuses fail closed
- recording-method values map exactly as frozen
- paging gathers all pages without duplication or truncation
- engine detachment completes pending reads exactly once
- every valid transaction passes `HealthWriteGuard.requirePhase1Transaction()`

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
