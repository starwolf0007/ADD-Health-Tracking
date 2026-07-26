# Fable 5 Multi-Prompt Audit — Reality vs. Fiction

**Date:** 2026-07-02 · **Verified against:** `starwolf0007/ADD-Health-Tracking` @ `f84609c` + `docs/NeuroFlow-Unified-Spec-v1.4.md`

## Verdict

The six prompts have the same disease as the last document reconciliation: **confident references to components that don't exist.** Of the major components the prompts name, roughly 60% appear nowhere in the repo or the spec. Two prompts (3 and 5) are built almost entirely on a fictional architecture; one prompt (3) directly **contradicts the locked spec** on palette and motion. Prompts 2 and 6 are the most grounded and are salvageable with corrections.

None of the prompts can be executed "in sequence" as written, because **the repo still does not compile** (`lib/presentation/today_screen.dart` and 8 other lib files remain truncated mid-line — confirmed again today). Spec §16's own language applies: nothing here is **Verified** until `flutter analyze` passes. Compile gate first, everything else second.

---

## Ground truth (what actually exists, verified by grep/read)

| Component | Status |
|---|---|
| `COMPILE_PATH.md` | ✅ Real (root) — references `v1.12.bundle`; repo contains `v1.16 (2).bundle` (internal version drift) |
| `android/.../LexiBridge.kt` | ✅ Real — 36-line stub, channel `neuroflow/lexi` |
| `lib/executive/lexi_plan_advisor.dart` | ✅ Real — `LexiPlanAdvisor` + `CloudGeminiPlanAdvisor`, MethodChannel `neuroflow/lexi` |
| `lib/core/lexi_mobile_prompt.dart` | ✅ Real |
| `PlanAdvisor` interface | ✅ Real — **`refine(Plan, List<Task>)`**, defined in `lib/executive/planner.dart` |
| `SyncQueue` | ✅ Real — a **Drift table** in `lib/platform/local/database.dart` (schema **v1**), drained by no worker yet |
| Google sync deps | ✅ In pubspec (`google_sign_in`, `googleapis`, `flutter_secure_storage`) — **zero implementation code** |
| Wear OS anything (`WearStateStore`, `NeuroFlowComplication`, `NeuroFlowTile`, `WearDataReceiver`) | ❌ Zero hits in code AND spec |
| `ForegroundSyncObserver`, `NeuroFlowDiagnostics` | ❌ Zero hits |
| `TodayContext`, `confidenceVelocity`, `ConfidenceOrbit`, `FsmMode`, `StopwatchTicker`, `LexiChatOverlay` | ❌ Zero hits in code AND spec |
| `TaskTelemetry`, `AiProposal`, `SyncOutbox`, `applyTaskMutation`, Gates/Musk/Page/Brin layers | ❌ Zero hits in code AND spec |
| `weeklyInsightProvider`, `todayContextProvider`, `secure_token_store.dart` | ❌ Zero hits |
| 872-line `today_screen.dart` | ❌ Real file is **435 lines and truncated** at `shape: RoundedRect` |
| Schema v5 | ❌ `schemaVersion => 1` |
| Sleep / heart-rate Quick Wins signals | ❌ Spec §6: trigger is **mood check-in + no-interaction nudge**. Zero mentions of sleep or heart rate anywhere. |
| Palette `#00BFA5` / `#E0E0E0` | ❌ Spec §13 locks `#0c0c0d` / `#2FB083`. |

## Real bugs the audit surfaced (new since RECONCILIATION.md)

1. **Split-brain platform channel.** Dart calls `checkGeminiNanoAvailable` / `generateResponse`; Kotlin only handles `ping` / `isAvailable`. Two different AIs wrote the two halves against two different contracts. It degrades safely today (notImplemented → MissingPluginException → NoOp), but Prompt 1 instructs the next AI to wire `ping()/isAvailable()` — which would "fix" the wrong side. **Fixed in this package:** Kotlin now serves the Dart names (Dart wins — the full advisor logic lives there).
2. **Four-layer boundary violation.** `lexi_plan_advisor.dart` (imports `flutter/services`, is AI) lives **inside `lib/executive/`**. Every prompt's own hard rule ("no AI import ever touches executive/") is violated by file placement. **Fixed in this package:** moved to `lib/intelligence/`, imports updated, composition root repointed. Delete the two old `lib/executive/lexi_*` files when applying.
3. **LexiBridge is never registered.** No `MainActivity` exists; the plugin would throw `MissingPluginException` forever → Lexi permanently silent even after SDK integration. **Fixed:** `MainActivity.kt` provided (lands after `flutter create` per placement note).
4. **`NetworkType.not_required` is CORRECT — Prompt 6's flagged "mismatch" is a false alarm.** Verified against workmanager 0.5.1 source on GitHub: the 0.5.x enum is snake_case (`not_required`); camelCase `notRequired` only arrives in 0.6+. Pubspec pins `^0.5.2`, which cannot auto-resolve to 0.6. **No change needed** — but if the team ever bumps workmanager past 0.6, this line breaks by design.

---

## Prompt-by-prompt scorecards

### Prompt 1 — "senior engineer, Pixel Watch 4"
- **Step 1 (audit + fixes):** Legitimate — already delivered (see RECONCILIATION.md + this package).
- **Step 2 (Lexi bridge):** Real target, **wrong contract** — says wire `ping()/isAvailable()` and `improve(PlanningContext, Plan)`. Actual interface is `refine(Plan, List<Task>)` and the Dart channel methods above. Contract fix delivered here; SDK integration (real Gemini Nano call) needs hardware + AICore, correctly a human/device step.
- **Steps 3–4 (polish, Wear hardening):** Polish list is reasonable *guidance* but conflicts with the truncated reality; **the entire Wear section is fiction** — no watch module, no spec support, and "Wear 4 Kotlin / MethodChannels / complication" targets hardware the spec never mentions. Building it now is scope creep against your own scope-cap principle.
- **Step 5 (failure injection):** `NeuroFlowDiagnostics` doesn't exist; fine as a *future* dev-tool idea, premature pre-compile.
- **Step 6 (`ForegroundSyncObserver.flush()`):** The class doesn't exist. What exists: `SyncQueue` table + `_enqueueMirror()` writing to it, and a code comment deferring the drain worker to §12.2 fast-follow. The real task is "write the sync worker that drains SyncQueue via googleapis" — after compile + OAuth.

### Prompt 2 — "lead technical architect" (most self-aware)
- Explicitly asks to verify against real code — good instinct, and here's the answer:
- **Sync race conditions:** Premature but legitimate. `SyncQueue` exists as an outbox table; there is **no field-level merge engine** to walk through yet. The conflict algorithm is a design task for the sync worker, not a review of existing code.
- **Exact alarms:** Real gap. Repo uses `flutter_local_notifications` + `workmanager`; **no `SCHEDULE_EXACT_ALARM` in the manifest**, no permission flow. Legit work item post-compile.
- **Quick Wins trigger:** **Correct the signal list.** Spec §6 locks: mood check-in (5-point) + no-interaction nudge. Sleep/heart-rate is invented — and would drag in Health APIs the scope cap excludes. Also: no `mood` table exists in either database file yet; signal ingestion is genuinely unbuilt.
- **On-device LLM bridge:** Already exists (see ground truth) — the prompt says "no bridge exists," which is stale. Task is now *contract hardening + SDK integration*, not greenfield design.

### Prompt 3 — "Steve Jobs Lens" ⛔ QUARANTINE
- Gates/Musk/Page/Brin layers, `TaskTelemetry`, `AiProposal → Commit → ApplyMutation`, `SyncOutbox`, `confidenceOrbitSegments`, `weeklyInsightProvider`, `FsmMode`, `lexi v14.4-mobile injected via TodayContext`: **none of it exists in code or spec.**
- **Directly contradicts locked spec:** palette `#00BFA5`/`#E0E0E0` vs. locked `#2FB083`; a per-second stopwatch ticker + ConfidenceOrbit animation vs. locked "no idle motion." 
- Do not hand this to any AI as-is. If the Confidence Orbit / telemetry ideas are features you *want*, they're spec-change proposals first (your own §16 process), not implementation orders.

### Prompt 4 — "Distinguished Engineer, 1M users"
- Harmless but premature. A ten-year architecture review of a repo that doesn't compile produces fiction by construction. Park until Phase 1 is Verified. (One of its questions is already answered: the plugin seam exists — `PlanAdvisor` — and it's clean.)

### Prompt 5 — "872-line today_screen refactor" ⛔ QUARANTINE
- The 872-line file doesn't exist (435 lines, truncated). `TodayContext`, `confidenceVelocity` (0.5–2.0), `ConfidenceOrbitPainter`, `LexiChatOverlay`, `applyTaskMutation`: all fictional. Same disease as Prompt 3 — likely the same source. The *actual* today_screen rebuild is already delivered in this package against the real `todayControllerProvider` contract.

### Prompt 6 — "review and harden" (most grounded — use this one, corrected)
| Item | Verdict |
|---|---|
| 1. §2.8 sensitive-data gate audit | §2.8 is real and locked. **Audit result: no sensitive tables exist yet** — no mood, no energy-state log, no medication flag in schema v1. The gate can't leak what isn't stored; the real task is to build the gate INTO the data-layer rebuild (checklist below). |
| 2. LLM bridge design | Bridge exists; path is `lib/intelligence/` (not `lib/executive/`, and the prompt's `lexi_plan_advisor.dart in lib/intelligence/` was the *correct* target location — the code was in the wrong folder, now fixed). |
| 3. OAuth token store | Real gap, deps present, zero code. Legit post-compile work item. Scope note: spec says `calendar.readonly` read-first + `drive.file` — keep it. |
| 4. NetworkType | **False alarm — resolved with source receipt (see bug #4 above).** |
| 5. Design tokens | Original presentation files already used `AppColors.*` tokens throughout (no raw `Colors.blue` drift found) — the failure was the truncated theme not *defining* them. Fixed theme in this package defines every referenced token. |
| 6. Compile path | `COMPILE_PATH.md` is real and its backup-first process is sound. Its bundle version reference (v1.12) is stale vs. the committed v1.16 bundle. |
| 7. Executive determinism | `planner.dart` imports domain only ✅. Violation was file placement (bug #2), now fixed. `QuickWinsMode` currently keys off task energy, not the spec's mood signal — flagged as gap, blocked on the mood table existing. |

## §2.8 never-sync checklist (for the database.dart rebuild)

When Claude Code rebuilds the data layer, the gate is structural, not aspirational:

1. Sensitive tables (`MoodLogs`, energy-state history, any habit flagged `isMedication`) get **no `googleTaskId` column and no companion in `_enqueueMirror`** — they physically cannot enter `SyncQueue`.
2. `SyncQueue.payloadJson` is built from an explicit **allowlist DTO** (title, due, status, listName) — never `toJson()` on a full row.
3. `CloudGeminiPlanAdvisor.refine()` receives `Plan` + `List<Task>` only — the type signature already makes mood/meds unreachable. Keep it that way: **never widen the PlanAdvisor signature to a context object containing sensitive rows.**
4. One unit test per sensitive table asserting nothing lands in `SyncQueue` after a save.

## Corrected sequential work order (what "in sequence" should actually be)

1. **Compile gate** — apply this package + RECONCILIATION.md cleanup, Claude Code rebuilds `lib/data/database.dart` (mine the complete Gen-B `lib/platform/local/database.dart` — it's spec-aligned: EnergyTag ×4 + SyncQueue), `build_runner`, `flutter analyze` clean. *(Blocks everything.)*
2. **EnergyLevel → EnergyTag decision** (RECONCILIATION.md decision #1) — do it during step 1 while there's no real data.
3. **Bridge contract** — apply the Kotlin fix + MainActivity from this package. SDK integration is device work.
4. **Mood table + Quick Wins signal** — build the 5-point check-in primitive, wire the mood trigger per spec §6 (replaces today's task-energy heuristic).
5. **OAuth + secure token store** — Prompt 6 item 3 as written, minus the fiction.
6. **Sync worker** — drain `SyncQueue` via googleapis; NOW Prompt 2's conflict-resolution question becomes answerable against real code.
7. Exact alarms manifest + permission flow (Prompt 2 item 2).
8. Only after all of the above is Verified: polish pass, failure injection, ten-year review. Wear OS: **spec-change proposal or drop.**
