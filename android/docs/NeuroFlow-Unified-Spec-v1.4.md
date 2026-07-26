# NeuroFlow — Unified Specification v1.4

**Status:** Locked baseline · **Date:** 2026-06-29 · **Owner of this doc:** Coordinator (Claude)
**Consolidates:** NeuroList · RoutineFlow · Proddy (Atomic Habits & Daily Routine) · TickTick-for-ADHD setup guide
**Replaces:** paid NeuroList + RoutineFlow subscriptions
**Contributors:** Grok · ChatGPT · Gemini · Claude

> **Changes in v1.4** (native rebase):
> - **Platform → native Flutter (§3).** Web/PWA dropped; the driver was web push reliability (~33%) being unfit for an ADHD reminder app. Native owns local notifications + exact alarms at the root.
> - **§2.8 data-governance principle:** sensitive class (mood, energy, meds) is on-device-only, enforced in code.
> - **§14 AI tiering:** Lexi on-device (Apple Foundation Models / Gemini Nano, seeded from her persona files); cloud Gemini opt-in only; deterministic Executive never depends on AI.
> - **Reconciled web-era artifacts:** §9 push workaround obsoleted (native owns notifications), §12.1 roles locked (Claude builds, three review), §12.2 tiers native-adjusted (PWA dead, widgets/tile reopened).
> - **§10 resolved:** OCR (ML Kit on-device), OAuth (native + Production-unverified), sweep 14/21d, cache TTL 48h, skip-budget 4/mo, trigger signal, outbound-as-native.

> **Changes in v1.3** (four-way design cross-check):
> - **Palette locked (§13):** background `#0c0c0d` near-black; accent muted emerald/teal (`#2FB083`). Not pure black, not phosphor/electric.
> - **Energy icons (§13):** flat monochrome glyphs, shape-distinguished — no color, preserving the one-accent rule.
> - **Heartbeat line (§13):** static fill, updates on state transition only — no idle/ambient animation.
> - **Quick Wins (§6):** **architecture LOCKED to automatic mode-swap** — Today reshapes itself when signals indicate a lighter day, showing only the capped (≤3, lowest-effort-first) tasks plus a small status label, with no separate screen, no manual filter/toggle, and no user action to trigger or maintain it. Invariants (cap, selection, reassurance label, signal-driven entry/exit) locked with it.

> **Changes in v1.2:**
> - **Design language locked (§13).** "Calm-functional, feedback-rich, explicitly not gamified," bound to the §2 principles the same way scope and integration decisions are. Every UI choice now runs through this filter.

> **Changes in v1.1** (folded from the group's day-in-the-life simulations):
> - **(A) Push the bad-day intervention.** The low-energy "one easy win" nudge now fires *outward* through the OS trigger layer instead of waiting for Bryan to open the app. Fixes the pull-based loop that defeated the point for an initiation deficit. → §2 (new principle 7), §3, §6.
> - **(B) Photo-snap verification step.** Throwaway snaps are no longer deleted at extraction. They're held in a short-lived local cache with a visual confirmation of what got extracted, then expire. → §4.2, §5, §7, §9.
> - **(C) Forgiveness mechanic + resurfacing.** Binary streaks replaced by completion-rate + a monthly skip budget. Stalled Inbox captures get a quiet, energy-matched resurfacing pass before the sweep archives them. → §4.1, §6, §8, §9.
> - **Meta-correction:** v1.0 assumed a user who reliably shows up to the app. v1.1 assumes the opposite — the user is as inconsistent as the disorder guarantees — and reaches outward in the gaps.

---

## 1. What this is

NeuroFlow is a single, self-hosted, Google-native ADHD productivity app that merges habit tracking, timed routines, mood/energy reflection, and one-off task management into **one cohesive place** — not another silo. It runs on Bryan's own hardware, syncs deeply with the Google ecosystem he already lives in, and is governed by a hard scope cap so it stays a workshop, not a museum.

This document is the consolidation baseline. Every "in" decision below carries a **rule** beside it; the rules are the deliverable, because they're what keep each feature from quietly growing into the bloated version later.

---

## 2. Design principles (non-negotiable)

These override feature requests, including future ones.

1. **Reduce friction, never add complexity.** A feature that doesn't lower the cost of capture or execution doesn't ship. "It's technically possible" and "it's Google" are not reasons.
2. **Workshop, not museum.** Capped configuration. Stale tasks get actively swept, not hoarded. The backlog is never allowed to become a guilt machine.
3. **Systems, not willpower.** The app does the remembering, scheduling, and surfacing. Bryan brings attention, not discipline.
4. **No shame spiral.** On bad days the app shows less, not more. Default views are small. Misses are silent.
5. **Cohesion through convergence, not screens.** Three ways in, one Inbox, one task object. New capture methods converge on the existing pipeline; they never get their own parallel UI.
6. **OS provides the mic, app provides the brain.** Anything the operating system already does well (voice-to-text, contact resolution, triggers, alarms) is consumed, not rebuilt.
7. **The app reaches outward; it never waits to be opened.** *(v1.1)* An initiation deficit means the highest-value moments — the bad-day nudge, the resurfacing of a stalled capture — cannot depend on Bryan choosing to navigate into the app. They are *pushed*. The app must not assume the capacity it exists to compensate for.
8. **Sensitive data is on-device-only, and the routing is enforced, not intended.** *(v1.4)* A defined sensitive class — mood logs, energy states, and medication-type habits (the 💊 case) — is **never eligible for the cloud AI tier**, full stop. "Never send medical data to the cloud" is only as strong as the classifier behind it, so the on-device-only boundary is a code-enforced gate (§14), not a guideline. This carries the same weight as the scope principles above.

---

## 3. Architecture overview

*(v1.4: rebased from self-hosted web to native. The switch was driven by web push reliability (~33%) being unfit for an ADHD reminder/alarm app — native gives real local notifications + exact alarms at the root.)*

| Layer | Decision |
|---|---|
| **Client** | **Native cross-platform app — Flutter/Dart**, running on Bryan's phone (iOS + Android). No web app, no PWA. |
| **On-device storage** | Local-first via Drift/SQLite — **source of truth** for the full Task record (incl. all extended fields). Robust local storage is now first-class (see §4 refinement). |
| **Host / NAS role** | Demoted to **optional**: Home Assistant on the DXP2800 can supply *supplementary* triggers; the NAS can hold an optional encrypted backup. The core app no longer runs on the NAS. |
| **Auth** | Native `@gmail.com` OAuth (`google_sign_in`) for Tasks, Calendar, Gmail, Drive, Contacts; tokens in platform secure storage (Keychain/Keystore). Consent screen Production-unverified (§12.3). (Keep excluded — §7.) |
| **Reminders / triggers** | *(v1.4 — changed)* **The native app owns local notifications and exact alarms directly.** This is the reason for the rebuild. The bad-day nudge and resurfacing are scheduled in-app (Executive→Platform), no external delivery dependency. Home Assistant / Assistant routines drop from *required delivery mechanism* to *optional supplement* and may also write into the Inbox (inbound). |
| **AI** | On-device by default (Lexi via Apple Foundation Models / Gemini Nano), cloud Gemini opt-in only, sensitive class on-device-only. Full tiering in **§14**. |
| **Sync model** | Local Drift DB is source of truth. Two-way mirror to Google Tasks/Calendar (the subset Google can hold). Read-only/pull for assist (Gmail, Contacts). Behavioral layer (habits/routines/moods) is app-native, optional encrypted backup to Drive. |

**Architectural seam worth naming:** Google has no primitive for habits, timed routines, mood logs, or streak/heatmap stats. That behavioral layer is **NeuroFlow-native**. The Google spine covers tasks, time, and capture; NeuroFlow owns behavior and reflection. Clean division, no impedance mismatch.

**Implementation skeleton — four layers** *(v1.4)*: Presentation (Flutter UI) → Executive (context snapshot, next-best-action, momentum + Quick Wins rules) → Platform (notifications, widgets, storage, OS, sync), with Intelligence (Lexi on-device + optional cloud adapter) plugging into an Executive-owned interface. **Hard rule: Executive never depends on Intelligence being available** — it runs a complete deterministic planner; AI is an optional enhancer, never a dependency.

---

## 4. Data model

### 4.1 Primitives

| Primitive | Origin | Syncs to | Notes |
|---|---|---|---|
| `task` | NEW | Google Tasks (2-way) | The missing primitive. Backbone of capture. See §4.2. |
| `habit` | Existing build | App-native | Recurring; **completion-rate + monthly skip budget (forgiveness mechanic)**, 5-week heatmap. *No binary all-or-nothing streak.* *(v1.1)* |
| `routine` | Existing build | App-native | Ordered timed steps; "habit stack" run-mode. |
| `mood` | Existing build | App-native | Daily 5-point check-in; feeds momentum insight + Quick Wins trigger. |
| `settings` | Existing build | App-native | Name, preferences. |

> Behavioral primitives (`habit`, `routine`, `mood`) persist locally and back up to Drive via JSON export. They are not forced into any Google shape.

### 4.2 The Inbox-ingestion contract (canonical task object)

**This is the architectural keystone.** All three capture rails terminate here and produce exactly this shape. Previously unowned; defined here as the baseline. Any rail that can't emit this object isn't done.

```jsonc
Task {
  "id":           "string",                 // app-generated
  "title":        "string",                 // the actionable text
  "source":       "quickadd|gmail|photo|os",// which rail produced it
  "status":       "inbox|today|scheduled|done|archived",
  "due":          "ISO-8601 | null",        // from NLP parse or Calendar
  "energy":       "low|deep|phone|waiting | null",  // see §6
  "priority":     "high|normal",            // two levels only — no priority sprawl
  "list":         "string | null",          // maps to a Google Tasks list
  "contactRef":   "string | null",          // raw name for resolve-on-view; NOT a stored number
  "attachmentRef":"drive-file-id | null",   // only when image has lasting value (§7)
  "snapRef":      "cache-id | null",         // v1.1: short-lived local cache pointer to source photo (unconfirmed); expires after confirm/TTL (§5, §7)
  "confirmed":    "boolean",                 // v1.1: photo-extracted items start false until visually confirmed; non-photo sources default true
  "googleTaskId": "string | null",          // sync linkage to Google Tasks
  "createdAt":    "ISO-8601",
  "completedAt":  "ISO-8601 | null"
}
```

**Contract rules:**
- A snapped "milk, eggs, bread" becomes **three** Task objects, identical to three typed lines. No rail gets a special object type.
- `priority` is deliberately two-valued. No P1–P4 ladders. (Cap.)
- `contactRef` stores the **name string only**. Numbers are resolved on view by the OS, never persisted into the task. (§7 Contacts.)
- `attachmentRef` is null for throwaway capture snaps. Drive only holds lasting-value images. (§7 Drive.)
- *(v1.1)* `snapRef` points to the source photo in a short-lived **local** cache (not Drive) so the user can verify a photo extraction. It is cleared when `confirmed` flips true or when the cache TTL expires, whichever comes first. `snapRef` and `attachmentRef` are mutually exclusive: throwaway snaps use `snapRef` (ephemeral), lasting-value images use `attachmentRef` (Drive).
- *(v1.1)* `confirmed` gates nothing destructive but drives the verification UI: photo-sourced tasks surface a "is this right?" affordance until confirmed.

---

## 5. Capture: three rails → one Inbox

Bryan's premise is "one cohesive place." That holds only if every capture method lands in the same Inbox and emits the same Task. It does.

### Rail 1 — NLP quick-add (primary)
- Typed or spoken sentence → parsed locally for date, time, and list. "Call dentist tomorrow at 2pm" self-schedules.
- **Voice is covered by the Gboard mic in the quick-add field** — no dedicated in-app voice feature (§7).
- **Parsing is local (chrono-style), not an LLM call.** Instant, offline, free. Do not spend a model call on date parsing.

### Rail 2 — Gmail suggest → approve
- One-tap "scan recent mail for action items / appointment confirmations → propose tasks."
- **Read-only. Pull, not push. Suggest, never auto-create.** Proposed tasks wait for Bryan's approval before entering the Inbox. An always-on agent silently manufacturing tasks rebuilds the guilt backlog by automation — that's the failure mode this rule exists to block.

### Rail 3 — Photo-snap
- Snap a photo to add a todo, a shopping/grocery item, or capture a document/receipt.
- OCR pass → **the existing AI breakdown engine extracts discrete items** → Inbox. (The "turn this blob into clean items" engine is already built; photo-snap just feeds it a camera instead of a keyboard.)
- **Verification step *(v1.1, fix B)*:** after extraction, show a quick visual confirmation — the extracted items beside (or over) the source photo — so a wrong "tortillas" gets caught before it becomes a confidently-wrong task. The source image is held in a **short-lived local cache** (`snapRef`), *not* deleted at extraction. On confirm, the tasks flip `confirmed: true` and the cached photo expires; if the user never confirms, the cache clears at TTL anyway. This preserves the verification path without hoarding images, and protects the one thing the whole product depends on: **trust in capture.**
- **Storage rule:** an image goes to **Drive only when it has lasting value** (receipt, document, whiteboard) via `attachmentRef`. Throwaway grocery/todo snaps never touch Drive — they live in the ephemeral local cache and expire. *(v1.1 amends the old "discard at extraction" rule: cache-then-expire, not immediate delete.)*

> **Convergence requirement:** Photo-snap and Gmail do **not** get their own lists or screens. They are sentences arriving at the same Inbox. If either grows a parallel UI, the core goal is violated — cap or no cap. *(The verification step is a transient confirmation surface, not a parallel screen.)*

---

## 6. Energy model & views

### Energy tags (replaces the old "habit categories" idea)
- Fixed set, capped: **`low-energy` · `deep-work` · `phone` · `waiting`** (3–5 max, no user-defined sprawl).
- Maps to **capacity**, not topic — which is why it beats category tagging for ADHD.

### Default view
- **Today + Inbox only.** The full backlog is never the landing surface.

### Quick Wins (the bad-day fallback)
A **reshaped state of Today**, not a screen and not a manual filter — **containment is the feature**, not the selection logic.

**Architecture — LOCKED (v1.3): automatic mode-swap of Today.** When the signals indicate a lighter day, **Today reshapes itself automatically** to show only the capped low-effort tasks plus a small status label. **No separate screen, no manual filter toggle, no user action to trigger or maintain it.** The reduction happens *to* Bryan; he never has to choose it, which is the whole point — the day he needs it most is the day he has the least capacity to go find it.

**Locked invariants (v1.3):**
- **Hard cap: ≤ 3 items.** An uncapped low-energy list can still surface fifteen tasks, and fifteen tasks on a bad day is still a shame pile. The cap is the mechanism; `energy:low-energy AND priority:normal` is just how candidates are found.
- **Selection rule when >3 qualify: lowest estimated effort first.** The point is momentum, not coverage.
- **Status label, not a control:** a small label communicates that Today is in its lighter state and ends with *"Nothing else is tracked today."* — explicit permission to stop. It is informational; there is no toggle to flip it on or off.
- **Entered and exited automatically by signal**, never by tap. This is what makes the two already-locked behaviors native rather than bolted-on: the rough-mood collapse and fix A's pushed nudge both *are* triggers of this mode-swap.

- **Trigger — in-app signal (mood):** a rough mood check-in reshapes Today into the capped state. No manual filtering on the day you have the least capacity to filter.
- **Trigger — pushed intervention *(v1.1, fix A — the core fix)*:** the bad-day nudge does **not** wait for app-open. The OS trigger layer (Home Assistant / Assistant routine) pushes a single gentle surface *to* Bryan — "rough one? here's one easy win" — naming one Quick-Wins item with a one-tap done, deep-linking into the already-reshaped Today.
  - Trigger source can be an explicit rough check-in **or** an inferred low-engagement signal (e.g. no app interaction by a set time) — exact signal is an open decision (§10).
  - Frequency cap: **one** nudge, not a stream. A nagging nudge is just notification spam wearing a kind face.
- **Exit:** Today returns to its normal shape automatically when the signals lift (e.g. a later non-rough check-in, or the next day). No "turn it off" affordance to find or forget.

### Stale-task sweep + resurfacing (workshop-not-museum, enforced)
- **Resurfacing pass *(v1.1, fix C)* — happens *before* archival:** a captured-but-stalled Inbox task gets one quiet, energy-matched resurfacing *before* it can be swept — surfaced (in-app, or pushed via the trigger layer) when Bryan is in a matching state: *"you grabbed 'order PETG' — still want it?"* This connects capture to recall, which is the entire point of capturing. Without it, frictionless capture is just a nicer way to forget things.
- Inbox tasks still untouched **after** the resurfacing pass, for **N days**, auto-move to `archived` (out of all default views).
- **Archived, not deleted** — recoverable, surfaced in a periodic digest, never a nag.
- This is automatic. Bryan never has to "clean up." The app prunes itself — but it taps you on the shoulder once before it does.

---

## 7. Google integration ledger (locked)

| Wire-in | Status | Rule that keeps it inside the cap |
|---|---|---|
| **Tasks** | Spine | Backbone task object; 2-way sync. |
| **Calendar** | Spine | 2-way; absorbs the old "scheduled-times" feature — the parsed "2pm" *is* the calendar block. |
| **Gmail** | In · read-only | Suggest → approve. Never auto-create. Pull only. |
| **Drive** | In | Store images **with lasting value only** (`attachmentRef`). Throwaway snaps **never touch Drive** — they sit in a short-lived **local** cache for verification, then expire *(v1.1: cache-then-expire, not immediate delete)*. Also the backup target for the behavioral-layer JSON. |
| **Contacts** | In · read-only | Resolve-on-view, silent no-match, **one behavior**: actionable contact tasks ("call X", "text Y") get a tap-to-call/text affordance. No contact-book sync, no enrichment, no write. |
| **Photo-snap** | In | Third capture rail → same Inbox, same Task. AI engine extracts; **visual verification step before commit, source cached locally then expires** *(v1.1)*. |
| **Voice capture (in-app)** | **Out** | Gboard mic already does voice-to-text system-wide in the quick-add field. Building a dedicated feature is duplication of a thing Bryan already uses — fails the friction bar. Requirement is satisfied; just not by us. |
| **Lock-screen / watch voice widget** | **Out** | No exception. OS bridge (Shortcut/Assistant → Inbox) covers capture-without-opening. |
| **Keep** | **Out** | Official API is enterprise/Workspace-only (domain-wide delegation); no personal `@gmail.com` OAuth. Unofficial scraper is unsanctioned and breaks without warning — nothing load-bearing on it. *Intent survives in the capture rails; the API does not.* |
| **Assistant routines (as a feature)** | **Out** | Trigger layer, already resolved. Assistant can write "remember X" into the Tasks Inbox — that's Bryan configuring Assistant against a spine surface we already own, not an integration NeuroFlow builds. |

**Through-line:** "All-in on Google" means **fewer surfaces that sync deeply**, not more surfaces because the API exists. Cohesion = two spine syncs (Tasks, Calendar) + one read-only assist (Gmail) + one on-demand contact action + one storage binding (Drive) — all converging on one Inbox and one Task. That's the whole list.

---

## 8. Feature set

### Already built (prototype) — folds in directly
- **Today dashboard** with completion ring.
- **Mood check-in** (5-point) → feeds momentum insight + Quick Wins trigger.
- **Habits** — daily/day-specific scheduling, **completion-rate + monthly skip budget (no binary streak)** *(v1.1)*, 5-week history heatmap.
- **Routines / habit stacks** — ordered timed steps, full-screen **run-mode** that walks one step at a time (the NeuroList focus + RoutineFlow/Proddy routine timer, unified).
- **AI breakdown engine** — turns a messy task into ordered, time-estimated steps. **Reused as the photo-snap extractor.**
- **Stats** — 14-day completion trend, **completion-rate / momentum (replaces best-streak)** *(v1.1)*, total completions, **mood-to-momentum insight** ("on good-mood days you finish ~X vs ~Y on rough ones").
- **Local persistence + JSON export** — portability hook; Drive is the backup target.

### New in unified scope
- **Tasks** primitive + **Inbox** + Today/Inbox default view.
- **Three capture rails** (§5) converging on the Inbox-ingestion contract.
- **Energy tags + Quick Wins** (§6).
- **Stale-task sweep** (§6).
- **Google spine sync** (Tasks, Calendar) + **assist** (Gmail suggest, Contacts resolve-on-view).
- **Photo-snap → OCR → extract** pipeline.

### New in v1.1
- **Pushed bad-day nudge** — outbound "one easy win" via the OS trigger layer, not app-open (§6, fix A).
- **Photo-snap verification step** — cache + visual confirm before commit, then expire (§5, fix B).
- **Forgiveness mechanic** — completion-rate + monthly skip budget replacing binary streaks (§4.1, §8, fix C).
- **Resurfacing pass** — one quiet, energy-matched recall of a stalled capture before the sweep archives it (§6, fix C).

---

## 9. Explicitly out of scope (and staying out)

Listed so they can't be re-litigated casually: dedicated in-app voice capture · lock-screen/watch voice widget · Google Keep sync · Assistant-as-an-integration · Contacts enrichment/suggestions/write · per-rail parallel screens · multi-level priority ladders · user-defined tag sprawl · **binary all-or-nothing streaks** *(v1.1: replaced by the forgiveness mechanic)* · **Drive storing throwaway snaps** *(v1.1: those go to the ephemeral local cache, never Drive)*.

**Updated in v1.4 — NeuroFlow now owns notifications directly.** The v1.1 clarification ("NeuroFlow owns no native push; the OS trigger layer delivers it") was a **web-era workaround** and is now obsolete. The native app schedules **local notifications and exact alarms itself** — that root-cause fix (vs web's ~33% push reliability) is the entire reason for the native rebuild. Home Assistant / Assistant routines remain available as an *optional supplement* (and as an inbound Inbox writer), but are no longer the required delivery mechanism. §2.6 still holds for voice and contacts; it simply no longer has to cover reminders. The following remain out: lock-screen/watch voice capture, Assistant-as-an-integration (it may write to the Inbox, that's all).

Each is out for a *reason* in §7/§6, not by oversight. Reopening one requires beating the principle that blocked it.

---

## 10. Open dependencies & ownership

Resolved here:
- ✅ **Inbox-ingestion contract** — drafted (§4.2). Needs an owner to ratify and implement as the shared interface all rails build against.

Still needs owners / decisions:
- ✅ **OCR engine** — *resolved (v1.4):* Google ML Kit on-device text recognition for all common capture; cloud never required.
- ✅ **OAuth specifics** — *resolved (v1.4):* native `google_sign_in` + secure storage; consent screen Production-unverified (no self-hosted server to stand up).
- ✅ **Stale-sweep threshold + resurfacing timing** — *resolved (v1.4):* resurface at 14 days untouched, archive at 21, weekly digest.
- ✅ **Photo cache TTL** — *resolved (v1.4):* 48 hours.
- ✅ **Skip-budget size** — *resolved (v1.4):* 4 / month.
- ✅ **Bad-day trigger signal** — *resolved (v1.4):* explicit rough check-in OR inferred (no interaction past a configurable hour, default 11:00, with tasks pending); inferred kept conservative.
- ✅ **Outbound trigger contract** — *resolved/obsoleted (v1.4):* native owns notifications, so the nudge is an in-app scheduled local notification `{taskId, title, body, deepLink}`; HA/Assistant is optional supplement, not required delivery.
- ✅ **Build lane assignment** — *resolved:* Claude builds (Flutter), Gemini/ChatGPT/Grok review (§12.1).
- ⬜ **On-device LLM bridge (Lexi)** — *new, open:* no stable Flutter package for Apple Foundation Models / Gemini Nano; this is a per-platform channel to write. Top build risk (§14).

---

## 11. Suggested build phasing

1. **Spine first** — Task primitive + Inbox-ingestion contract + Google Tasks/Calendar 2-way sync. Nothing else works without the backbone.
2. **Rail 1** — NLP quick-add (local parser) on top of the contract. Capture is the whole point; get it frictionless first.
3. **Fold in the behavioral layer** — port the existing build (habits, routines/run-mode, mood, stats, heatmaps) onto the unified app shell. **Port habits with the forgiveness mechanic, not binary streaks** *(v1.1)*.
4. **Energy model + views + outbound layer** — tags, Today/Inbox default, Quick Wins, stale-sweep **+ resurfacing pass**. Stand up the **outbound trigger-layer contract** and the **pushed bad-day nudge** here — this is fix A and it's load-bearing, not a polish item *(v1.1)*.
5. **Rail 3 (photo-snap)** — OCR → existing AI engine → **verification step + local cache** → Inbox. Drive only for lasting-value images *(v1.1)*.
6. **Rail 2 (Gmail) + Contacts** — the read-only assists last, since they're enhancements on a working core.

Each phase ships a usable app. No phase depends on a later one. *(v1.1 note: the outbound nudge in phase 4 depends on the trigger layer existing — if OAuth/host bring-up slips, the in-app Quick-Wins collapse still ships and the push lands when the layer's ready.)*

---

## 12. Build, deployment & technical hardening (v1.1 addendum)

### 12.1 Dev model — who builds what *(v1.4: roles locked)*
Native Flutter build. One builder, three reviewers, Bryan compiles/runs.

| Piece | Owner |
|---|---|
| **Flutter/Dart implementation** (the actual app) | **Claude (this thread)** — writes correct, idiomatic source; cannot compile/device-test from chat. |
| Cross-reference review | **Gemini** (architecture/research) · **ChatGPT** (layered-architecture/technical) · **Grok** (pragmatic build-detail) — reviewers only, *not* parallel builders. |
| Compile, device test, OAuth/on-device-model bring-up | **Bryan's environment** (Flutter SDK + Xcode/Android Studio, ideally driven by Claude Code on the desktop). |
| Home Assistant config (optional supplement) | Bryan; builder drafts, Bryan validates. |
| Spec source-of-truth | This document. |

**Note on "porting":** the React prototype is now a **design/interaction reference only** — React does not cross to Dart, so it seeds the look and the mechanics, not the codebase.
**Build-lane rule:** one builder + others as red-team/review. Four AIs writing into one repo recreates the fragmentation this consolidation exists to kill.

### 12.2 Service activation tiers *(v1.4: native-adjusted)*
- **v1 must:** Google Tasks (spine) · **native local notifications + exact alarms** (the bad-day nudge ships in-app, no external dependency) · Calendar **read-only** display.
- **Fast-follow:** Calendar two-way write · Drive backup (`drive.file`) · photo-snap + on-device OCR + Drive image storage (one unit).
- **v2:** Gmail suggest · Contacts resolve-on-view.
- **Reopened by going native:** **home-screen widget / Quick Settings Tile / App Intents** were cut in v1.1 as "overkill" — but that rationale was web-era. Native makes them cheap and idiomatic, and a one-tap capture/quick-win surface fits the spec well. **Reconsider for fast-follow**, not v1.
- **Dead (native):** PWA install target · IndexedDB-in-hooks persistence note (§12.3) — native gets first-class local storage for free.
- **Sequencing honesty:** a real, useful v1 ships Tasks + capture + behavioral layer + the in-app Quick-Wins mode-swap, with the local-notification nudge as the first thing after the usable core.

### 12.3 Technical hardening (newly raised)
1. **Google Tasks has no custom fields** — and native resolves this more cleanly than v1.1 imagined. Its model is title/notes/due/status/subtasks; the extended Task fields (`energy`, `priority`, `snapRef`, `confirmed`) cannot round-trip. *(v1.4)* With native first-class local storage, the **local Drift DB holds the full Task record and is the source of truth**; Google Tasks is a mirror of only the subset it can hold, linked by `googleTaskId`. There is no separate extended-fields store — the local row *is* the record. Defines the §4 sync conflict policy.
2. **OAuth token longevity.** Refresh tokens expire every **7 days** while an External app's consent screen is in **"Testing."** Fix: publish to **Production-unverified** — valid for personal use under 100 users (one "unverified app" warning at sign-in), tokens then persist, and it avoids Google's verification/CASA assessment. *Do not ship in Testing mode.*
3. **Scope minimization.** Narrowest scope per service: `drive.file` (app-created files only, never full Drive) · `calendar.readonly` first · **zero Contacts scope** — resolve via OS intents, not the People API · `gmail.readonly` is the one unavoidable restricted scope (another reason Gmail is v2).
4. **Local-first / offline capture is mandatory.** Capture happens on gas routes with spotty signal. Writes hit local storage instantly; a sync queue flushes when online. Capture must never fail because the network did — existential for a capture-trust app.
5. **Encrypt the token store.** *(v1.4)* On native, use platform secure storage (`flutter_secure_storage` → iOS Keychain / Android Keystore) for the OAuth refresh tokens — don't hand-roll. The one security item not to skip.

---

## 13. Design language (locked)

**The language:** *calm-functional, feedback-rich, explicitly not gamified.*

Chosen over the playful-gamified direction (Finch/Forest) because gamification's reward/punishment loop is the same dopamine-cliff logic as the binary streaks we already removed — a withering pet is a shame mechanism with a face. Calm-functional is also the more durable bet: gamification has a novelty half-life; calm-functional is what still gets opened in week three. The bar: *the best app is the one you'll still open after the first week — if opening it already feels overwhelming, it isn't helping.*

This binds to §2 the same way scope decisions do — **every UI choice must beat the principle it would otherwise violate.** The rules below each cite the principle they serve.

| Rule | Serves | What it means concretely |
|---|---|---|
| **Capture is reachable from anywhere in one gesture** | §2.1 (reduce friction), §2.7 (reach outward), §5 capture-trust | A persistent capture affordance on *every* surface — never a screen you navigate to. The moment of capture is unpredictable; if it requires navigation, the thought is already gone. The single most important flow rule for this app. |
| **One primary action per screen** | §2.1 (no complexity), §2.3 (systems not willpower) | Every screen answers "what do I do here?" in under a second, with one visually unmistakable action. Choice is the tax that triggers paralysis. Run-mode (one step, one button) is the gold standard for *all* screens, not just routines. |
| **Depth hidden by default** | §2.2 (workshop not museum) | Stats, full backlog, settings, configuration are reachable but never in the primary path. Tools live in the drawer, not on the bench. Flat, shallow navigation — no deep trees to get lost in. Progressive disclosure throughout. |
| **Motion confirms state, never performs** | §2.1 (reduce noise), §5 capture-trust | Movement shows *where things went* (a capture flying to the Inbox, a task settling out) so a time-blind brain can track state — reassurance, not flourish. No decorative animation. **The Today "heartbeat" progress line is a *static fill* that updates only on a state transition — no idle or ambient animation** *(v1.3)*. Always respect reduced-motion settings (motion sensitivity is real in this population). |
| **Dark / restrained palette, one accent reserved for action** | §2.1 (reduce visual noise), §2.4 (no shame spiral) | Low-stimulus base. Exactly **one** accent color, and it means *action / the thing to do now* — never spent on decoration. **Locked values *(v1.3)*: background `#0c0c0d` near-black (not pure `#000000` — pure black causes more halation/smear on OLED while scrolling); accent muted emerald/teal (working value `#2FB083`, adjustable within the muted range, never toward phosphor/electric).** Calm is the retention strategy; color is a signal, not a texture. |
| **Energy icons: monochrome glyphs, shape not color** *(v1.3)* | §2.1 (one visual language), §13 one-accent rule | The four energy tags (`deep-work` · `phone` · `low-energy` · `waiting`) are distinguished by **shape**, rendered as flat monochrome glyphs. Color-coding the icons would create a second signal layer competing with the one action-accent — so the accent stays the only color that means anything. |

**Feedback-rich, not gamified — the distinction that keeps it from going sterile:** reward the *action* (satisfying microinteractions, visible momentum, accomplishment-proof stats) — never gamify the *person* (no points, characters, streaks-as-stakes, or withering-pet pressure).

**Out, as decoration that fights the language:** glassmorphism, bento-grid layouts, 3D/spatial, AR, heavy gamification skins. All trend-y in 2026; all add visual noise and load time in a context where calm and speed *are* the product. (Speed is a design decision — heavy assets are exactly what an attention-fragile user can't afford.)

**Adopt, as function not fashion:** purposeful microinteractions (state confirmation) · gesture navigation (swipe to complete/archive/back — fewer visible controls, faster feel) · progress made visible (counters ADHD's distorted sense of accomplishment).

**Locked tokens (v1.3) — single source of truth for mockup and build:**
| Token | Value | Note |
|---|---|---|
| Background | `#0c0c0d` | Near-black. Not pure `#000000`. |
| Accent (action only) | `#2FB083` (muted emerald/teal) | The entire signal layer. One value, one meaning. Never phosphor/electric. |
| Energy icons | monochrome glyphs | Shape-distinguished; no color. |
| Heartbeat line | static fill | Updates on state transition only; no idle motion. |

> **Not in this lock batch:** typography (recommended: sans-serif primary, monospace reserved for live numerals only) was ruled on in cross-check but not included in Bryan's v1.3 decision list — left out of the locked rules pending explicit sign-off.

---

## 14. AI architecture & model tiering (locked, v1.4)

NeuroFlow runs AI in tiers, defaulting to on-device. **Lexi** (Bryan's persona) runs as the on-device model — **Apple Foundation Models** on iOS, **Gemini Nano** on Android — seeded with her saved persona/knowledge as the system prompt (her existing `bryan_deep_profile` / `lexi_self_profile` / `shared_experiences` files), **not** a live call to the hosted Gemini Gem.

**Tier table — every AI-touching feature declares its tier:**

| Feature | Tier | Rule |
|---|---|---|
| NLP quick-add date/time parsing | **None (deterministic)** | Local chrono-style parser. No model call. (§5) |
| Executive next-best-action / Quick Wins / momentum | **None (deterministic)** | Pure rules. Intelligence may *enhance* but Executive never depends on it (§3 skeleton). |
| Magic breakdown (task → steps) | **On-device default** | Lexi on-device. Cloud only as explicit opt-in for a hard case. |
| Photo-snap item extraction | **On-device default** | ML Kit OCR → on-device model cleanup. |
| Big re-plans / heavy reasoning | **Cloud opt-in only** | Cloud Gemini, never automatic, always user-initiated. |
| Anything touching the sensitive class | **On-device-only — cloud forbidden** | Enforced gate (see below). |

**The sensitive-data gate (binds §2.8):** mood logs, energy states, and medication-type habits are a defined sensitive class that is **never eligible for the cloud tier**. This is enforced in code — the cloud adapter cannot be handed sensitive-class data, by construction, not by prompt instruction. "Never send medical data to the cloud" is only as strong as this classifier.

**Honest quality caveat (the reason tiering exists):** on-device models (Foundation Models, Gemini Nano) are markedly weaker than cloud Gemini — small parameter counts, tight context. Breakdown/extraction quality drops and gets more variable on-device. That is *expected*, and the cloud opt-in is the escape hatch — but the default stays on-device for privacy, offline capability, and the §2.8 guarantee. The deterministic Executive means the app stays fully usable even when the on-device model is cold, slow, or unavailable.

**Top build risk:** there is no stable Flutter package for either on-device model. The Lexi bridge is a per-platform method channel (Swift ↔ Foundation Models, Kotlin ↔ Gemini Nano) we write. Nothing else blocks on it — Intelligence plugs into an Executive-owned interface, so the app ships and runs on the deterministic planner until the bridge lands.

---

*Baseline updated to v1.4 — rebased from self-hosted web to **native Flutter** (§3), added the §2.8 on-device data-governance principle, the §14 AI tiering architecture, and reconciled the now-obsolete web-era push workaround (§9), dev-model roles (§12.1), and service tiers (§12.2). The §10 implementation decisions are resolved (OCR, OAuth, sweep/TTL/skip-budget values, trigger signal, outbound-as-native). Design language (§6, §13) is unchanged and ports directly. Changes go through the principles in §2 — a feature or UI choice must beat the rule that would otherwise exclude it.*

