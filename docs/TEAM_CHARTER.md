# TEAM CHARTER — v3
> Project: **NeuroFlow** (repo: ADD-Health-Tracking). This file defines who does what, the rules that never change, and how work passes between AIs. Whichever AI is currently active reads this file and HANDOFF.md before doing anything. The active AI IS the Head Coordinator for that session — the role belongs to whoever holds this charter, not to any one model.

---

## 1. The team

**Owner / Product Lead:** Bryan. Final say on everything. Works on a budget — all AI usage is free tier. Sessions end when tokens/credits run out, so every session must end handoff-clean.

**Core rotation (can each act as Head Coordinator):**
- **Claude** — Chief Builder. Primary architecture and implementation.
- **ChatGPT** — Builder / reviewer. Picks up implementation mid-stream.
- **Grok** — Builder / reviewer. Same.
- **Gemini** — Thought partner. Design reasoning, tradeoff analysis, planning. Does not integrate with the toolchain — Gemini output is advisory until a builder implements and verifies it.

**Contractors (scoped tickets only — never open-ended work):**
- **Devin** — free tier, ~1 month cooldown. Burn its runs on execution, not context-gathering.
- **Qodo** — free tier, ~1 month cooldown. Same.
- **GitHub Copilot / GitHub AI** — verification and in-repo review. Per §3, Copilot toolchain verification outranks any chat-based claim.

## 2. Locked design decisions (no AI may change these without Bryan)
1. Native Flutter/Dart. Four layers: Data → Platform → Executive → Presentation. Executive never imports Intelligence.
2. Local-first Drift/SQLite; Riverpod; SyncQueue for Google Tasks/Calendar.
3. One accent color **#2FB083**, for action only.
4. No visible scores or numbers in UI.
5. Quick Wins are derived, never stored.
6. No binary streaks — completion-rate + monthly skip budget.
7. Suggest-never-silently-mutate for pattern adjustments.
8. NoOpPlanAdvisor is the null-object default.
9. ANCHORS + FLEX: mornings are a fixed routine script; evenings are fluid prioritization.
10. Timeline shows "the way back in, not just the day behind."

## 3. Verification rules
- Nothing earns **Verified** status unless the toolchain actually ran it (build, tests, analyzer).
- Copilot/toolchain verification carries higher authority than any chat-based claim by any AI, including the Coordinator.
- Every "done" claim in HANDOFF.md must carry a commit hash.

## 4. Contractor ticket format
Contractors get one ticket per run. A ticket must contain:
- **Scope:** one feature or fix, named files/dirs
- **Acceptance criteria:** what passing looks like (tests, behavior)
- **Do-not-touch list:** files/branches that are mid-work per HANDOFF.md §3
- **Branch:** where to work and where to PR

## 5. The handoff protocol
1. **Session start:** AI reads TEAM_CHARTER.md, then HANDOFF.md, then confirms understanding in one short summary before touching code.
2. **During:** Commit early, commit small, reference commits in conversation.
3. **Session end (or tokens running low):** AI rewrites HANDOFF.md completely — objective, done-with-hashes, in-progress, next 3 steps, landmines, branch status — and Bryan commits it. No session ends without this.
4. **Stale-file rule:** If HANDOFF.md's date is older than the latest commits, trust git log and say so.

## 6. Standing priority
Until resolved: rotating the leaked Firebase credentials and scrubbing google-services.json from history outranks all feature work.
