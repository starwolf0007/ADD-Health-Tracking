# HANDOFF — The Football
> **Rule:** This file is overwritten at the END of every work session, by whichever AI did the work. The next AI reads this FIRST, before writing any code. If this file is stale, trust the git log over this file.

**Last updated:** 2026-07-14
**Updated by:** Claude (Chief Builder)
**Session #:** 001

---

## 1. Current objective
Stand up the multi-AI handoff system. Immediate priority: **rotate the Firebase credentials leaked in google-services.json** (committed to public repo), then purge it from git history. (Untracking + .gitignore is already done — see §5; rotation and history purge are NOT.)

## 2. Done this session (verified with commit hashes)
| What | Commit | Verified by |
|---|---|---|
| Stale-branch report workflow (PR #12, merged to main) | 9e575c8 | GitHub Actions run #1 succeeded (manual dispatch; correctly found 0 stale branches) |
| Transition design docs + ADR-007 (PR #13, open draft) | f8a404f | Repo Hygiene CI passed on PR #13 |
| Added TEAM_CHARTER.md + HANDOFF.md + HANDOFF_PROMPTS.md under docs/ | 4391b9c | — |

> "Done" without a commit hash is not done. Per Charter: nothing is Verified unless the toolchain ran it.
> **Note:** these files live in `docs/`, not the repo root — the Repo Hygiene CI check fails any new root-level `.md` file. The session-start prompt's "read TEAM_CHARTER.md, then HANDOFF.md" means `docs/TEAM_CHARTER.md` and `docs/HANDOFF.md`.

## 3. In progress / half-finished
- PR #13 (branch `claude/stale-branch-report-action-s6obkb`): transition-first decision record, transitions UX spec, routine-evolution mapping, ADR-007, plus these handoff files. Open as draft awaiting Bryan's review/merge. Design-only — no code.
- The transition docs reference `core-principles.md` and `Transition-Routines-Proposal.md`, which do not exist in the repo yet. Dangling until added.

## 4. Next 3 steps (in order)
1. Rotate Firebase keys; remove google-services.json from history (git filter-repo or BFG); already in .gitignore
2. Audit diverged branches — list every branch, what's unmerged, and decide merge/kill for each (starting point: §6 table below, verified 2026-07-14)
3. _(Next feature work)_

## 5. Blockers & warnings (landmines)
- ⚠️ google-services.json: untracked + gitignored since commit 86733e0 (2026-07-09, with a `.example` template) — **but the real file is still retrievable from git history on the public repo.** Credentials must be rotated and history purged (filter-repo/BFG + force-push). Verified still-in-history on 2026-07-14.
- ⚠️ Multiple diverged branches with unmerged work — do not assume main is current
- ⚠️ History purge rewrites main — coordinate with Bryan before any force-push; all clones/branches need re-basing afterward

## 6. Branch status (verified against origin, 2026-07-14)
| Branch | State | Action needed |
|---|---|---|
| main | current (9e575c8) | — |
| claude/stale-branch-report-action-s6obkb | open draft PR #13 (docs only) | review + merge |
| fix/alpha-task-start-timer | active — last commit 2026-07-14 | continue |
| starwolf0007-patch-1 | inactive since 2026-06-30 (13 days) — hits the 14-day stale threshold 2026-07-15; the Monday stale-branch report will flag it | decide merge/kill |
| devin/1783633400-refactor-shared-utils | last commit 2026-07-09 | audit (step 2) |
| devin/1783633353-domain-unit-tests | last commit 2026-07-09 | audit (step 2) |
| devin/1783633052-improve-error-handling | last commit 2026-07-09 | audit (step 2) |
| devin/1783633146-security-audit | last commit 2026-07-10 | audit (step 2) |
| claude/app-handoff-wcijhg | last commit 2026-07-10 | audit (step 2) |

## 7. Contractor tickets outstanding
- _(Tickets handed to Devin / Qodo / Copilot — see TEAM_CHARTER.md §4. One line each: ticket, contractor, status.)_
