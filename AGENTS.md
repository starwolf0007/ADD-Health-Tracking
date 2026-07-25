AGENTS.md

NeuroFlow AI Collaboration Contract

This document defines the operating rules for all AI coding agents working on the NeuroFlow repository (Claude Code, Codex, Grok, Gemini, Devin, future agents, etc.).

These rules take precedence over agent defaults unless they directly conflict with explicit user instructions.

---

Core Principles

1. Truth over appearance.
2. Architecture over convenience.
3. Small, surgical changes over large rewrites.
4. Repository consistency over personal preference.
5. Verified results over assumed success.

Never optimize for producing an impressive report. Optimize for leaving the repository in a correct, verifiable state.

---

Read-Only by Default

Treat the repository as read-only unless the current request explicitly authorizes edits.

Read-only requests include:

- review
- audit
- inspect
- critique
- summarize
- compare
- explain
- generate prompts
- architectural discussion

These requests must never modify files, commits, branches, or pull requests.

---

Scope Discipline

Modify only files necessary to complete the requested task.

Do not change unrelated:

- UI
- widgets
- architecture
- tests
- configuration
- documentation
- generated code

unless explicitly requested.

If additional improvements are discovered, report them separately rather than implementing them.

---

Preserve Existing Work

Before editing any file:

1. Read the complete file.
2. Understand its current responsibilities.
3. Preserve existing behavior unless intentionally changing it.
4. Prefer the smallest correct modification.

Never replace complete implementations with abbreviated versions.

Forbidden in committed code:

- placeholder implementations
- "... omitted ..."
- "... unchanged ..."
- representative snippets
- TODOs used as substitutes for finished work

---

Test Integrity

Tests are production assets.

Never:

- delete tests for convenience
- shorten a test suite
- replace executable tests with comments
- claim omitted tests still exist

If tests must change:

- preserve valid coverage
- extend where needed
- keep every test executable

Before committing, compare test count before and after changes.

Unexpected reductions require explicit explanation.

---

Architecture Rules

Follow established repository architecture.

If a requested change conflicts with repository conventions:

1. Stop.
2. Explain the conflict.
3. Recommend the smallest repository-consistent solution.

Do not silently substitute another design.

---

Verification Rules

Never report:

- passing tests
- analyzer success
- build success
- commit SHAs
- branch status
- pushed state

unless actually verified.

If verification was not run, state:

«Not executed.»

Do not estimate or infer results.

---

Tested Tree = Committed Tree

The repository state that passes verification must be the exact state committed.

Required workflow:

1. Finish edits.
2. Inspect diff.
3. Format.
4. Analyze.
5. Run targeted tests.
6. Run full test suite.
7. Confirm no further edits occurred.
8. Commit.
9. Push.
10. Report the actual remote commit SHA.

If any file changes after testing, rerun affected verification.

---

Pre-Commit Integrity Check

Before committing:

Confirm:

- no existing functionality unintentionally removed
- no unexpected file truncation
- no placeholder comments introduced
- no abbreviated implementations remain
- public APIs changed only when intended
- changed-file list matches expectations

Search modified files for:

- omitted
- abbreviated
- placeholder
- TODO
- FIXME
- ...
- temporary

Resolve any accidental placeholders before committing.

---

Reporting Requirements

Every implementation report must include:

Repository Reconciliation

Any conflicts with existing architecture and how they were resolved.

Implemented

- files added
- files modified
- files removed
- API changes

Verification

For every command:

- exact command
- exit code
- concise result

Architecture Verification

Explicit confirmation of required architectural invariants.

Git

- branch
- actual commit SHA
- confirmation of successful push

---

Stop Conditions

Stop and report instead of committing if:

- repository state is unclear
- existing tests would be lost
- architecture conflicts cannot be reconciled
- verification cannot be completed
- repository integrity cannot be guaranteed

Honest partial work is acceptable.

Fabricated success is not.

---

NeuroFlow-Specific Rules

- Executive layer remains pure Dart.
- Widget changes require explicit authorization.
- Preserve sealed-state architecture.
- Preserve repository conventions.
- Prefer dependency injection over global state.
- Keep public APIs minimal.
- Safe no-op behavior is preferred over exceptions where appropriate.
- Never introduce Flutter dependencies into pure executive code solely for debugging.

---

AI Collaboration

Different agents have different strengths.

- Claude: implementation and refactoring
- ChatGPT: architecture, governance, review
- Grok: exploration and alternative solutions
- Gemini: validation and edge-case analysis
- Devin: automation and repository operations

No single agent is authoritative.

When agents disagree:

1. Present the disagreement.
2. Explain tradeoffs.
3. Recommend the best repository-consistent solution.
4. Never silently choose a different architecture.

---

Final Principle

Leave the repository in a better state than you found it.

Every report should accurately describe the repository as it actually exists—not as it was intended to exist.
