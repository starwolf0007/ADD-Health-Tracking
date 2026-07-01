# NeuroFlow — Build Notes v0.3 (Flutter native)

**Builder:** Claude (this thread) · **Reviewers:** Gemini (architecture/research) · ChatGPT (layered-architecture/technical) · Grok (pragmatic build-detail)
**Source of truth:** Unified Spec **v1.4** (design tokens §13, Quick Wins/Focus mechanics §6, AI tiering §14). This doc resolves the open §10 items *as build decisions* and records the stack + architecture the spec was deliberately platform-agnostic about.
**Status of code in this drop:** written, not compiled. Codegen (`build_runner`) and device runs happen in Bryan's environment. Reviewers cross-check design/structure; correctness-on-device is validated at compile.
**Repo:** `https://github.com/starwolf0007/ADD-Health-Tracking` — pull/access pending (clone returned 404 / auth-required as of this drop; see handoff note in chat). All files below are committed locally and ready to push once access is confirmed.

**v0.3 — Presentation layer (Today screen), first runnable UI:**
- `lib/presentation/theme.dart` — §13 locked tokens (`#0c0c0d` bg, `#2FB083` accent) realized as a single Flutter `ThemeData`. Nothing else in `presentation/` should hardcode a color.
- `lib/presentation/widgets/heartbeat_line.dart` — static-fill progress line; `TweenAnimationBuilder` only re-animates on value change, no `AnimationController` loop — satisfies the v1.3 "no idle motion" correction.
- `lib/presentation/widgets/energy_glyph.dart` — the four energy tags as monochrome, shape-distinguished icons (bolt / call / battery / hourglass), single neutral color, never the accent.
- `lib/presentation/widgets/capture_sheet.dart` — the realized "capture reachable from anywhere in one gesture" rule. **Phase note:** writes a plain Task with no `due` — the local NLP parser (§5 Rail 1) is phase 2 and slots into one `TODO` line here; UI doesn't change when it lands.
- `lib/presentation/today_screen.dart` — consumes `todayControllerProvider` only; zero knowledge of Drift/Riverpod plumbing. Renders both `TodayMode` states: the single Next-Best-Action card (normal) and the capped Quick-Wins list ending in the reassurance line (automatic mode-swap, locked v1.3/v1.4).
- `lib/main.dart` — entry point; one-time async init for notifications + WorkManager, then `ProviderScope` → `TodayScreen`.
- **Repository addition, flagged:** `TaskRepository.watchCompletedTodayCount()` (+ Drift query + provider). The heartbeat line needed a real ratio; nothing upstream produced one. Small, justified, not silent.
- **New dependency:** `uuid` (task id generation in the capture sheet).

**v0.2 — review pass cleared, two changes folded in before wiring:**
- **`PlanAdvisor` is now a null-object, not nullable.** `NoOpPlanAdvisor` is the default, identity-function implementation; callers always hold a non-null advisor. `Planner.nextAction` refactored into `orderedCandidates()` + pick, so the controller has a *list* to hand through `refine()` — Planner itself never imports or calls Intelligence.
- **Phase 1 drops `SCHEDULE_EXACT_ALARM`.** Android 12+ gates it behind a revocable permission, 13+ adds a runtime check — real friction for marginal precision gain on a "here's one easy win" nudge. Phase 1 uses `AndroidScheduleMode.inexactAllowWhileIdle` + WorkManager for periodic background eval (sweep, inferred-signal check). Exact alarms are a fast-follow if inexact proves too loose. Hardware note: target device confirmed Pixel 10 Pro **XL** — doesn't change the scoping, the gate is Android-version-based not device-based.

---

## 1. Stack (locked, open to reviewer challenge)

| Concern | Choice | Why / reviewer lane |
|---|---|---|
| Framework | **Flutter / Dart** | Locked by group. |
| State | **Riverpod**, plain (no generator) for phase 1 | Generator surface deferred — keeps codegen limited to Drift. (ChatGPT lane — confirm or push back.) |
| Persistence | **Drift over SQLite** | Local DB is **source of truth** for the full Task record (§3 v1.4 refinement, Gemini-reviewed); Google Tasks is a subset mirror via `SyncQueue`. (Grok lane.) |
| Notifications | **flutter_local_notifications + timezone, INEXACT (phase 1)** | Native ownership is why we rebuilt; exact alarms deferred — see v0.2 note above. |
| Background eval | **workmanager** | Periodic (hourly/daily) checks for the bad-day signal and the sweep — both tolerant of imprecise timing by nature. |
| OCR (photo rail) | **Google ML Kit Text Recognition (on-device)** | §10 resolved → on-device, offline, free. Cloud only if accuracy forces it. |
| Google sync | **google_sign_in + googleapis** | Tasks/Calendar via native OAuth. |
| Token storage | **flutter_secure_storage** | Keychain/Keystore — satisfies §12.3 "encrypt the token store." |
| NLP quick-add | **local parser, non-LLM** | §5 holds — date/time parsing stays deterministic/offline. |
| On-device LLM (Lexi) | **platform channel** to Apple Foundation Models (iOS) / Gemini Nano (Android) | ⚠️ no stable Flutter package exists — this is a per-platform bridge we write. Flagged as the top build risk. |

---

## 2. Four-layer architecture (adopted as skeleton)

```
Presentation (Flutter UI)            lib/presentation/
        │  depends on ▼
Executive (context, next-best-action, momentum, Quick Wins rules)   lib/executive/
        │  depends on ▼
Platform (notifications, widgets, storage, OS, sync)   lib/platform/ + lib/data/
Intelligence (Lexi on-device, optional cloud adapter)  lib/intelligence/
```

**The invariant — Executive never depends on Intelligence being available.** Enforced structurally, not by discipline:
- Executive imports **domain only**. It does **not** import `lib/intelligence/`.
- Executive owns an interface (`PlanAdvisor`) and runs a complete **`DeterministicPlanner`** by default. **(v0.2, post-review)** `PlanAdvisor` is a **null-object**, not a nullable type — the default implementation, `NoOpPlanAdvisor`, is the identity function. Callers always hold a non-null advisor; there's no scattered null-checking, and "Intelligence absent" is a normal code path instead of a special case.
- `Planner` never calls `PlanAdvisor` itself — `orderedCandidates()` returns the deterministic list, and **the orchestration layer** (`TodayController`) is the one and only call site for `.refine()`. Stricter than v0.1: Executive can't develop even an accidental runtime dependency on Intelligence, because it never references the interface's `refine()` method at all.
- Dependency arrow points inward (Intelligence → Executive's interface), never outward. So "AI is down / on a plane / model cold" degrades gracefully to deterministic behavior with zero code path missing — and with `NoOpPlanAdvisor`, this isn't a fallback branch, it's just what runs.

This is also why the app is usable before Lexi's bridge exists at all — phase 1 ships on `NoOpPlanAdvisor` and the deterministic planner, with the swap to the real Lexi bridge being a single provider override.

---

## 3. §10 decisions — resolved (several changed because we went native)

| § | Decision | Resolution | Native impact |
|---|---|---|---|
| OCR engine | on-device vs cloud | **ML Kit on-device** for all common capture; cloud never required | unchanged intent, now trivially available |
| OAuth specifics | self-hosted redirect/token mess | **native OAuth via `google_sign_in`; tokens in secure storage; consent screen Production-unverified** (still avoids the 7-day Testing expiry per §12.3) | **simplified** — no self-hosted server/redirect URIs to run |
| Sweep threshold `N` | pick day count | **resurface at 14 days untouched; archive at 21 days; weekly digest** | unchanged |
| Photo cache TTL | unconfirmed snap lifetime | **48 hours** | unchanged |
| Skip-budget size | forgiveness days/month | **4 / month** (~one a week) | unchanged |
| Bad-day trigger signal | explicit vs inferred | **both:** explicit rough mood check-in, **or** inferred (no interaction past a configurable hour, default 11:00, with tasks pending) — inferred kept conservative to avoid false positives | unchanged |
| Outbound trigger contract | payload to HA/Assistant | **changed → internal.** Native owns local notifications directly, so the bad-day nudge is scheduled Executive→Platform as a local notification carrying `{taskId, title, body, deepLink}` (`NudgePayload`, implemented). HA/Assistant downgraded from *required delivery* to *optional supplement* | **materially changed** — this was a web-era workaround |
| Exact vs inexact alarms | precision of the nudge timing | **resolved v0.2 (post-review): inexact for phase 1.** `AndroidScheduleMode.inexactAllowWhileIdle` + WorkManager for periodic eval. No `SCHEDULE_EXACT_ALARM` request. Fast-follow if inexact proves too loose | new decision, native-specific |
| Lane assignment | who builds | **closed** — Claude builds, three review | n/a |

**Hardware note (Bryan, confirmed):** target phone is **Pixel 10 Pro XL**. Doesn't change exact-alarm scoping (Android-version gate, not device-specific) — recorded for the record. **Pixel Watch 4 confirmed capable of running an actual companion app** (not just notification mirroring) — noted as a strong future surface for §2.7 (reach outward) and the bad-day nudge specifically, since on-wrist tap-to-done is lower-friction than the phone. Not started; flagged so Wear OS isn't designed against weaker assumptions later. When it comes up, §13's "capture reachable from anywhere in one gesture" will need an explicit phone+wrist amendment.

**Native-driven architecture refinement worth a reviewer eyeball (esp. Gemini + ChatGPT):**
The §12.3 "extended-fields store keyed by googleTaskId" gets simpler. With native local storage as first-class, the **local Drift DB is the source of truth holding the *full* Task** (all extended fields). **Google Tasks is a one-way-ish mirror of the subset it can hold** (title/notes/due/status). There is no separate extended-fields store — the local row *is* the record; `googleTaskId` just links it to its Google mirror. Cleaner than the spec imagined, because the spec imagined a self-hosted web app without robust local storage.

---

## 4. What's in this drop (phase 1 — the spine)

- `pubspec.yaml` — dependency lock (workmanager added v0.2; uuid added v0.3).
- `lib/domain/task.dart` — the canonical Task (spec §4.2) as an immutable Dart entity + enums. Pure domain, no Flutter/Drift imports.
- `lib/domain/task_repository.dart` — repository interface (Executive/Presentation depend on this, not on Drift). `watchCompletedTodayCount()` added v0.3 for the heartbeat line.
- `lib/platform/local/database.dart` — Drift schema: `Tasks` (full record incl. extended fields, `lastTouchedAt` for the sweep) + `SyncQueue` (pending Google mirror ops). Local-first source of truth. `@DataClassName('TaskRow')` avoids a name clash with the domain `Task`. `watchCompletedTodayCount()` query added v0.3.
- `lib/platform/local/task_repository_impl.dart` *(v0.2)* — `DriftTaskRepository`: local-first writes, best-effort Google-mirror enqueue, archive-not-delete.
- `lib/platform/notifications/notification_service.dart` *(v0.2)* — inexact local notifications; `NudgePayload` is the realized outbound-trigger contract.
- `lib/platform/background/background_scheduler.dart` *(v0.2)* — WorkManager periodic jobs for the bad-day signal eval and the sweep/resurface pass. Actual DB/notification wiring inside the callback is marked `TODO(integration)` — needs the real platform DB path, not fakeable from chat.
- `lib/executive/planner.dart` — `ContextSnapshot`, `Planner` interface (+ `orderedCandidates()`, v0.2), **`DeterministicPlanner`**, and **`NoOpPlanAdvisor`** (v0.2) implementing the Intelligence-independence invariant as a null object.
- `lib/app/providers.dart` — Riverpod composition root. Wires Platform → Executive → `TodayController`, the one call site for `PlanAdvisor.refine()`. `completedTodayCountProvider` added v0.3.
- `lib/presentation/theme.dart`, `widgets/heartbeat_line.dart`, `widgets/energy_glyph.dart`, `widgets/capture_sheet.dart`, `today_screen.dart` *(v0.3, new)* — see changelog above.
- `lib/main.dart` *(v0.3, new)* — app entry point.

## 5. What's next (phasing, from spec §11)
2. NLP quick-add (local parser) → wire into `capture_sheet.dart`'s one `TODO` line. 3. Port behavioral layer (habits/routines/mood/stats) onto the spine — `todayMoodProvider`/`lastInteractionProvider` are already stubbed in `providers.dart` for this. 4. Wire `BackgroundScheduler`'s `TODO(integration)` callbacks to real DB + `NotificationService` calls; sweep/resurfacing. 5. Photo rail (ML Kit → extract → 48h cache). 6. Gmail + Contacts. Lexi bridge slots into `planAdvisorProvider` whenever its platform channel is ready — nothing else changes.

## 6. Open questions for reviewers (round 2)
- **Grok:** WorkManager's 15-min Android floor / iOS background best-effort — acceptable for the bad-day check, or does the inferred-signal eval need tighter timing than "roughly hourly"? Also: `build_runner` codegen flow for Drift on Bryan's setup.
- **ChatGPT:** does routing `refine()` exclusively through `TodayController` (vs. inside `Planner`) satisfy the stricter boundary you asked for, or do you still want a separate package?
- **Gemini:** any objection to the local-first/Google-mirror refinement now that it's implemented in `task_repository_impl.dart`?
- **All three (new, v0.3):** the `watchCompletedTodayCount()` repository addition — reasonable, or should "today's progress" be computed a different way once habits/routines (phase 3) exist alongside tasks?
