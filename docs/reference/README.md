# External Reference Library

This directory holds NeuroFlow's external reference audits — real projects studied
for patterns worth adopting or explicitly rejecting, before new code gets written
for a feature area.

## Why this exists

Building every UX pattern and every architectural decision from a blank page is
slower than it needs to be, and reinvents problems other projects have already
solved. This directory is where "how did a proven project solve this?" gets
answered *before* implementation starts, not discovered by accident partway
through.

## Two separate reference systems — do not mix them

### Architecture Constitution (`architecture/`)

References that may influence correctness, data boundaries, domain design, or
data modeling decisions. These can change how `HealthTransaction`, the
repository layer, Drift schema, or evidence/sensitivity doctrine work.

### UX Pattern Library (`ux/`)

References that influence how NeuroFlow *feels* — interaction patterns,
language, pacing, visual polish. **A UX reference must never dictate the data
model.** A consumer app's friendly interface has no vote on `HealthTransaction`,
Drift, repository validation, or medical-sensitivity rules — those come only
from `architecture/` references and NeuroFlow's own doctrine.

## Reference statuses

Every entry in `reference-matrix.md` carries one of four statuses:

- **Verified** — canonical URL confirmed, repository content matches its
  described purpose, license and maintenance status checked, relevant files
  identified.
- **Provisionally verified** — the project is confirmed to exist and roughly
  matches its description, but one or more of the Verified criteria hasn't
  been checked yet.
- **Unverified** — claimed but not yet independently checked. Do not build
  doctrine or implementation decisions around an Unverified reference.
- **Rejected** — checked and found to be nonexistent, or checked and found to
  contradict its description badly enough that it isn't usable as a model.

Verified means the project has been accurately audited. It does **not** mean
NeuroFlow adopts the project's architecture or product philosophy wholesale.

## Adding a new reference

1. Copy `template.md` into `architecture/` or `ux/` as appropriate.
2. Fill in every section — an empty "Patterns to reject" section is a signal
   the reference wasn't actually scrutinized, not that it's flawless.
3. Add a row to `reference-matrix.md`.
4. If the reference influenced an actual NeuroFlow decision, say which one,
   specifically — not "informed our thinking."

## Review cadence

Re-review a reference when approximately twelve months have passed, when
NeuroFlow materially depends on one of its patterns, or when the upstream
project's license, maintenance state, or major version changes.

## What does not belong here

- Screenshots and other binary assets of third-party apps — link to the source
  instead.
- Personal exploration notes that haven't converged on adopt/reject decisions.
- Claims presented as verified without supporting inspection.
