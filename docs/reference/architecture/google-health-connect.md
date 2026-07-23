# Google Health Connect Samples and Codelab

## Status
Verified

## Reference category
Architecture Constitution

## Canonical source

- **Health samples:** `https://github.com/android/health-samples`
- **Codelab:** `https://github.com/android/android-health-connect-codelab`
- **License:** Apache License 2.0
- **SDK version used by NeuroFlow:** `androidx.health.connect:connect-client:1.1.0`
- **Maintenance status:** Maintained by the Android project

## Problem it solves

Health Connect provides a standard Android interface for reading health and
fitness records created by device sensors and third-party applications. Google's
samples define the platform-authoritative behavior for SDK availability,
permissions, bounded reads, paging, change tokens, upsertions, and deletions.

## Why NeuroFlow cares

Health Connect is NeuroFlow's first health-data sensor bus. The adapter must
preserve platform evidence and provenance without allowing Android SDK types or
provider-specific behavior to become part of NeuroFlow's domain model.

## Patterns NeuroFlow should adopt

- Stable, fail-closed availability mapping.
- Explicit permission mapping to NeuroFlow-owned wire keys.
- Bounded raw-record reads through `readRecords<T>()` and `TimeRangeFilter`.
- Preservation of `DataOrigin.packageName`.
- Independent start/end UTC instants and zone offsets.
- Paging until the bounded result is exhausted.
- Distinct handling of future Upsertion and Deletion changes.

## Patterns NeuroFlow should reject

> NeuroFlow uses `readRecords<StepsRecord>()` for evidence ingestion. It does
> not store aggregate totals as evidence. Records from different data origins
> remain independent even when their time ranges overlap. Aggregation and source
> reconciliation are derived operations performed after ingestion.

At ingestion, the adapter must never merge records, sum counts, choose a
preferred source, flatten intervals, discard competing evidence, or manufacture
a daily total. Once separate source evidence is flattened, its provenance cannot
be recovered. Any later daily total, provider reconciliation, or preferred-source
view is a derived operation over preserved source-level evidence.

Android Health Connect SDK objects and constants must not cross the platform
boundary. Native code emits plain transport values; Dart owns canonical parsing
and normalization.

## First implementation slice

```text
HealthConnectClient
    ↓
readRecords<StepsRecord>()
    ↓
one plain transport map per source record
    ↓
strict Dart parser
    ↓
one HealthSourceRecordDraft
    ↓
one HealthSpanDraft
    ↓
one validated HealthTransaction
```

For overlapping records:

```text
watch StepsRecord → HealthTransaction A
phone StepsRecord → HealthTransaction B
```

One upstream Health Connect record produces one `HealthTransaction`.

## HealthConnect Steps Transport v1

The MethodChannel boundary is a versioned internal API. The payload is a closed
result envelope:

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

Rules:

- `records` is always present and is always a list.
- `ok` with an empty list means the read succeeded and no matching records exist.
- `unavailable` means Health Connect is unavailable.
- `permission_denied` means required read permission is absent or was revoked.
- `failed` means another native read failure occurred.
- Unknown statuses fail closed as `failed` in Dart.
- Native exception messages, stack traces, and class names never cross the channel.
- `sourceAppId` is required; missing or blank provenance is a malformed record.
- Android recording-method integers are mapped to the stable strings above in Kotlin.
- No field may be renamed, removed, repurposed, or overloaded without incrementing the transport version.

## Recording-method normalization

The wire preserves the Health Connect distinction between automatic and active
recording. NeuroFlow's current domain enum intentionally maps both to genuine
device measurement:

```text
automatic → RecordingMethod.deviceMeasured
active    → RecordingMethod.deviceMeasured
manual    → RecordingMethod.userEntered
unknown   → RecordingMethod.importedUnknown
```

`sourceEstimated` and `sourceDerived` are not used for raw Steps records unless a
future source explicitly supplies inferred or computed evidence.

## Transport fields for Steps

Preserve external record ID, record type, step count, start/end instants,
start/end zone offsets, data-origin package, source last-modified instant,
client record ID/version when present, and recording method.

Do not transport daily totals, merged intervals, preferred-provider decisions,
inferred device names, health interpretation, or derived analytics.

## Relevant source files and modules

- `health-connect/HealthConnectSample` in `android/health-samples`
- the codelab's `start` and `finished` modules
- permission, availability, bounded-read, and changes-token examples

## License and attribution notes

Apache License 2.0. This architecture-tier reference may directly inform the
platform adapter, while NeuroFlow continues to own its transport contract,
domain model, validation, and evidence doctrine.

## NeuroFlow decisions influenced

- Confirmed PR #22's closed availability-state mapping.
- Locked `readRecords<StepsRecord>()` rather than `aggregate()` for ingestion.
- Locked one upstream record to one `HealthTransaction`.
- Required an overlapping-source regression test.
- Frozen the Steps v1 MethodChannel envelope and recording-method wire values.
- Reinforced checkpoint advancement only after successful repository commit for
  later incremental-sync work.

## Last reviewed

- **Date:** 2026-07-23
- **Reviewer:** NeuroFlow engineering review
