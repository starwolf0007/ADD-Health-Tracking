# Reference Matrix

Status definitions and the adopt/reject process are in `README.md`. Full
write-ups live under `architecture/` and `ux/`; this table is the index.

Verified means accurately audited. It does not mean NeuroFlow adopts every
pattern from that project.

## Architecture Constitution

May influence `HealthTransaction`, Drift schema, repository boundaries, or
evidence/sensitivity doctrine.

| Reference | Status | Role | Doc |
|---|---|---|---|
| `android/health-samples` | Verified | Health Connect platform authority — permission flow, change tokens, Upsertion/Deletion handling | `architecture/google-health-connect.md` |
| `android/android-health-connect-codelab` | Verified | Companion learning flow to the above | `architecture/google-health-connect.md` |
| `the-momentum/open_wearables_health_sdk` | Verified | Kotlin↔Flutter bridge shape and multi-provider transport pattern; backend sync model not adopted | not yet written |
| `health_connector` | Verified | Type-mapping and timestamp-handling comparison | not yet written |
| `karlicoss/HPI` | Verified | Local evidence-vs-derived philosophy and source-adapter pattern | not yet written |
| Open mHealth | Verified | Schema-completeness comparison for canonical health events | not yet written |
| StudyU / `studyu-v2` | Verified | N-of-1 trial lifecycle and evidence model | not yet written |
| StudyMe | Verified | Self-directed N-of-1 trials for non-expert users | not yet written |
| `CHUV-PCL/Nof1Companion` | Verified | Clinical N-of-1 trial workflow | not yet written |
| `erikkktv/biohacking-n-of-1` | Verified — early stage | Pre-registration discipline; methodology reference only | not yet written |
| Tidepool | Verified | Patient-owned health-data philosophy and clinical rigor | not yet written |
| Mere Medical | Verified | Offline-first personal health-record reference | not yet written |
| `tech.mmarca.openvitals` | Provisionally verified | Local-only, read-only Health Connect dashboard; canonical source/file audit still needs confirmation | not yet written |
| `mandarnilange/health_tracker_reports` | Verified | Local-first Flutter health app using Hive rather than Drift | not yet written |
| Leantime | Verified | Goal-to-planning-to-execution information architecture for neurodivergent users | not yet written |

## UX Pattern Library

Influence feel only. **Never a vote on the data model, Drift, repository
validation, or medical-sensitivity rules.**

| Reference | Status | Role | Doc |
|---|---|---|---|
| Goblin Tools | Verified | Task decomposition and one-next-step philosophy | not yet written |
| Finch | Verified | Encouraging language; pet/streak/guilt mechanics rejected | not yet written |
| Google Tasks | Verified | Fast entry and restrained Material interaction | not yet written |
| AppFlowy | Verified | Mature Flutter navigation and offline-first patterns | not yet written |
| Super Productivity | Verified | Task planning and time-block patterns | not yet written |
| Tasks.org | Verified | Android offline task and scheduling patterns | not yet written |
| Logseq | Verified | Local-first knowledge interaction patterns; UX-tier only | not yet written |
| RoutineFlow | Unverified | Claimed one-step routine execution and gentle pacing | not yet written |
| Neurolist | Unverified | Claimed low-friction brain-dump capture | not yet written |
| Inku | Unverified | Claimed calm calendar and companion-presence patterns | not yet written |

## Rejected or superseded claims

| Reference or claim | Status | Reason |
|---|---|---|
| Claim that `erikkktv/biohacking-n-of-1` was fabricated | Superseded | Direct README inspection confirmed the project exists. A failed search is not proof of non-existence. |
