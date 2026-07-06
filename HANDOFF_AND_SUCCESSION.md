# NeuroFlow — Handoff & Succession

*Written for the next engineer to own this project. Everything here describes the code that actually exists and compiles — not a plan, not a vision deck. Where something is unbuilt, it says so.*

---

## To the next lead engineer

You're inheriting a **local-first Flutter ADHD executive-function app** that compiles green and runs on a Pixel. It is deliberately small and deliberately disciplined. Before you change anything, understand three things:

**1. This is not a task manager. It's an executive-function prosthetic.** The single design principle everything serves: *optimize for the moment of return, not just the moment of action.* People with ADHD don't fail tasks while working — they fail at **returning** to interrupted work. Every design decision bends toward making the return effortless. If a change makes starting easier but returning harder, it's wrong.

**2. The organizing model is ANCHORS + FLEX.** The day is fixed pins (anchors: wake, morning routine, leave-by, dinner, bedtime) with flexible space between them (tasks, chores). Mornings are a *routine* problem (fixed, run like a script). Evenings are a *prioritization* problem (fluid). The app must serve both shapes. This came from the actual user and it's the truest thing in the project.

**3. This project's history is a cautionary tale about discipline.** Earlier iterations (before this codebase) collapsed under *fictional architecture* — multiple AI contributors generating confident code for components that didn't exist, two interleaved code generations in one repo, nine files truncated mid-line and committed without compiling. The recovery was: **rip it back to one coherent generation, get it compiling, then add one verified feature at a time.** The prime directive that came out of that: **compile before features, use before extending, one thing at a time.** If you break that discipline, you will reintroduce the exact failure mode that nearly killed the project.

### What worked well
- **Four-layer architecture with hard boundaries** (Domain / Data / Executive / Presentation, plus an isolated Intelligence seam). It's the reason fictional components never reached the binary — the boundaries make drift visible at compile time.
- **Local-first Drift as the single source of truth.** No network dependency for core function. The app works fully offline, forever.
- **The deterministic Executive** with the AI seam isolated behind one interface (`PlanAdvisor`). AI enriches the plan; it can never *become* the plan or break the morning.
- **Typed Drift tables.** Every entity (Task, Habit, Routine, Note, MoodLog) is properly modeled with its own fields. This type safety has caught real bugs repeatedly.

### High-risk areas — do not violate these
- **NEVER collapse the typed tables into one generic "event" table.** This was proposed repeatedly and rejected every time. The timeline (when built) is a **read-only projection** that queries across the typed tables and merges by timestamp — it is NOT a storage model anything writes to. Collapsing to a generic event bag destroys the type safety and recreates the untyped-mud failure mode. Present as events; persist as types.
- **NEVER let AI write directly to the database.** The `PlanAdvisor` seam returns a refined `Plan`; it does not mutate. "No silent mutation by AI" is a hard rule.
- **The Executive stays pure and synchronous.** `Executive.evaluate()` takes data in, returns a `Plan`, performs no I/O, no clock reads, no AI calls. Determinism is the contract — same inputs, same plan. The async AI seam lives in the controller, not the engine.
- **Mood/sensitive data is on-device.** `MoodLogs` has no sync columns by design. (Note: the user has since decided mood *should eventually* sync to Google Health — but that's a future opt-in mirror, not a change to the current on-device-only baseline. Don't add mood sync without building the explicit opt-in path.)

---

## Feature Completion Matrix

| Feature | Status | Notes / Remaining Work | Complexity to finish |
|---|---|---|---|
| Four-tab shell (Today/Notes/Routines/Reflect) | ✅ Complete | `app_shell.dart`, IndexedStack | — |
| Tasks (CRUD, energy, estimate) | ✅ Complete | Full domain + Drift + repo | — |
| Focus timer (count-up, haptics, overtime) | ✅ Complete | `focus_timer.dart`, wired into Today card | — |
| Notes (capture, pin, promote-to-task) | ✅ Complete | `notes_screen.dart` | — |
| Routines (one-step runner, seeds) | ✅ Complete | Morning Launch + evening wind-down seeded | — |
| Mood check-in (5-point) | ✅ Complete | Drives Quick Wins trigger | — |
| Quick Wins auto-mode (§6 trigger) | ✅ Complete | Mood ≤ Low reshapes Today, in `Executive.evaluate` | — |
| Forgiveness habits (streak, no shame) | ✅ Complete | `habits_widget.dart`, on Reflect tab | — |
| Leave-by countdown + behind-pace | ✅ Complete | `routine_pace_banner.dart`, scheduled routines only | — |
| Weekday-aware routines (`activeDays`) | ✅ Complete | Schema v2 migration; Morning Launch = Mon–Fri | — |
| Design system / tokens | ✅ Complete | `theme.dart`, two functional colors | — |
| Lexi advisor seam | 🟡 Partial | Interface + Dart advisor + Kotlin bridge stub exist; **on-device Gemini Nano SDK not wired** — advisor NoOps until `LexiBridge.kt` gets a real model call | High (needs AICore SDK + device testing) |
| **Your Day timeline** | ⬜ Planned | Next Phase 2 build. MUST be a read-only projection over existing tables. MVP = routines + task completions + mood markers. | Medium |
| **Living-state tasks (7 states)** | ⬜ Planned | Foundation for Phase 2. Replaces binary `TaskStatus`. Migration + Executive logic update. Build FIRST in Phase 2. | Medium |
| **Re-Entry Card** | ⬜ Planned | The signature feature. Depends on living-state + timeline. Reads timeline to find stall point. | Medium |
| Launch Mode / Recovery Mode | ⬜ Planned | Paralysis defenses (before-start / mid-task) | Low–Medium |
| Finish Line ritual ("Put Away 5") | ⬜ Planned | High impact, low complexity | Low |
| Pattern Learning (friction memory) | ⬜ Planned | On-device step-level stall memory. Feeds Lexi predictions. | Medium |
| Voice capture | ⬜ Planned | Phase 3. On-device speech + Nano parse. Ask-once-when-unsure. | Medium–High |
| Google Tasks/Calendar sync | ⬜ Planned | Phase 3. OAuth + `googleapis` (deps present, no code). | High |
| Calendar-aware routines | ⬜ Planned | Phase 3. Day-off/vacation detection. See CALENDAR-INTEGRATION-SCOPE.md | High |
| Two-way mood ↔ Google Health | ⬜ Planned | Phase 5 (after watch). Health Connect. | High |
| Pixel Watch companion | ⬜ Planned | Phase 5. Wear module + Data Layer. | High |

Legend: ✅ Complete · 🟡 Partial · ⬜ Planned

---

## Roadmap (from the actual codebase forward)

### Immediate priority — the compile-safe next steps
1. **Apply the pending weekday update** (if not already merged) — schema v2, requires `dart run build_runner build`.
2. **One week of real user use** before building Phase 2. This is a hard gate. Real friction data outranks design theory.

### Phase 2 — Executive Function Layer (build in this order)
1. **Living-state tasks** — the 7-state model. Foundation; everything references "Paused."
2. **Your Day timeline** — read-only projection. The canvas every later feature renders on. MVP first (routines + completions + mood).
3. **Re-Entry Card** — ships basic as soon as 1+2 exist. The signature feature.
4. **Launch Mode + Recovery Mode** — paralysis defenses.
5. **Finish Line ritual** — the putting-away micro-win.
6. **Weekly review** — science-informed (WHO-5/PERMA) reflection language.
- Support layer: **Pattern Learning** (friction memory), **Countdown timer mode**.

### Phase 3 — Google Ecosystem
Calendar-aware routines, Tasks/Calendar sync, voice capture, handwriting→task OCR. All need OAuth (user provides credentials).

### Phase 4 — Lexi Embedded
On-device Gemini Nano, adaptive planning, Pattern-Learning-driven stall prediction, mood-adaptive tone.

### Phase 5 & Beyond
Pixel Watch companion (then Google Health, which the watch enables), decision-paralysis engine, Runways, Mission grouping, Android Auto, NAS/Home Assistant, voice-first everything.

### The design filter for every future decision
**Every new feature must reduce decisions, not create them.** If a proposed feature adds management overhead without reducing cognitive load, don't build it. This one rule prevents the scope creep that nearly killed the project.
