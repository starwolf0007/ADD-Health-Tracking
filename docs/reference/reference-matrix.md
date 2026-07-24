# Reference Matrix

Status definitions and the adopt/reject process are in `README.md`. Full
write-ups live under `architecture/` and `ux/`; this table is the index.

Verified means accurately audited. It does not mean NeuroFlow adopts every
pattern from that project. A reference must have a completed audit document
before it can be marked Verified.

## Architecture Constitution

May influence `HealthTransaction`, Drift schema, repository boundaries, or
evidence/sensitivity doctrine.

| Reference | Status | Role | Doc |
|---|---|---|---|
| `android/health-samples` | Verified | Health Connect platform authority — permission flow, change tokens, Upsertion/Deletion handling | `architecture/google-health-connect.md` |
| `android/android-health-connect-codelab` | Verified | Companion learning flow to the above | `architecture/google-health-connect.md` |
| `the-momentum/open_wearables_health_sdk` | Provisionally verified | Kotlin↔Flutter bridge shape and multi-provider transport pattern; backend sync model not adopted | not yet written |
| `health_connector` | Provisionally verified | Type-mapping and timestamp-handling comparison | not yet written |
| `karlicoss/HPI` | Provisionally verified | Local evidence-vs-derived philosophy and source-adapter pattern | not yet written |
| Open mHealth | Provisionally verified | Schema-completeness comparison for canonical health events | not yet written |
| StudyU / `studyu-v2` | Provisionally verified | N-of-1 trial lifecycle and evidence model | not yet written |
| StudyMe | Provisionally verified | Self-directed N-of-1 trials for non-expert users | not yet written |
| `CHUV-PCL/Nof1Companion` | Provisionally verified | Clinical N-of-1 trial workflow | not yet written |
| `erikkktv/biohacking-n-of-1` | Provisionally verified — early stage | Pre-registration discipline; methodology reference only | not yet written |
| Tidepool | Provisionally verified | Patient-owned health-data philosophy and clinical rigor | not yet written |
| Mere Medical | Provisionally verified | Offline-first personal health-record reference | not yet written |
| `tech.mmarca.openvitals` | Provisionally verified | Local-only, read-only Health Connect dashboard; canonical source/file audit still needs confirmation | not yet written |
| `mandarnilange/health_tracker_reports` | Provisionally verified | Local-first Flutter health app using Hive rather than Drift | not yet written |
| Leantime | Provisionally verified | Goal-to-planning-to-execution information architecture for neurodivergent users | not yet written |

## UX Pattern Library

Influence feel only. **Never a vote on the data model, Drift, repository
validation, or medical-sensitivity rules.**

| Reference | Status | Role | Doc |
|---|---|---|---|
| Goblin Tools | Provisionally verified | Task decomposition and one-next-step philosophy | not yet written |
| Finch | Provisionally verified | Encouraging language; pet/streak/guilt mechanics rejected | not yet written |
| Google Tasks | Provisionally verified | Fast entry and restrained Material interaction | not yet written |
| AppFlowy | Provisionally verified | Mature Flutter navigation and offline-first patterns | not yet written |
| Super Productivity | Provisionally verified | Task planning and time-block patterns | not yet written |
| Tasks.org | Provisionally verified | Android offline task and scheduling patterns | not yet written |
| Logseq | Provisionally verified | Local-first knowledge interaction patterns; UX-tier only | not yet written |
| RoutineFlow | Unverified | Claimed one-step routine execution and gentle pacing | not yet written |
| Neurolist | Unverified | Claimed low-friction brain-dump capture | not yet written |
| Inku | Unverified | Claimed calm calendar and companion-presence patterns | not yet written |

## Rejected or superseded claims

| Reference or claim | Status | Reason |
|---|---|---|
| Claim that `erikkktv/biohacking-n-of-1` was fabricated | Superseded | Direct README inspection confirmed the project exists. A failed search is not proof of non-existence, and existence alone is not sufficient for Verified status. |
