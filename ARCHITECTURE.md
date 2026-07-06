# NeuroFlow — Architecture

*Describes the real, compiling codebase: ~41 Dart files, Flutter + Riverpod + Drift, local-first. Current through Phase 2 Steps 1–2 (living-state tasks + timeline projection).*

---

## The four layers (plus one seam)

NeuroFlow enforces a strict layered architecture. The layers are real — they're expressed in the import graph, and the boundaries are what kept fictional components out of the binary during the project's troubled history.

```
┌─────────────────────────────────────────────────┐
│  PRESENTATION  (lib/presentation/)               │
│  Screens, widgets, theme. Reads providers only.  │
│  Never touches Drift or repositories directly.   │
└───────────────────────┬─────────────────────────┘
                        │ watches
┌───────────────────────▼─────────────────────────┐
│  APP / COMPOSITION  (lib/app/)                   │
│  providers.dart — the ONLY file that knows every │
│  layer. focus_timer.dart — global timer state.   │
│  TodayController bridges Presentation ↔ Executive│
└───────────────────────┬─────────────────────────┘
                        │
┌──────────────────┬────▼──────────┬───────────────┐
│  EXECUTIVE       │  DATA         │  INTELLIGENCE  │
│  (executive/)    │  (data/)      │  (intelligence/)│
│  Pure planner.   │  Repos +      │  PlanAdvisor    │
│  Imports domain  │  Drift DB.    │  impls. The AI  │
│  ONLY. No I/O,   │  Source of    │  seam. Isolated │
│  no AI, no       │  truth.       │  so AI can't    │
│  Flutter.        │               │  leak elsewhere.│
└──────────────────┴───────┬───────┴───────────────┘
                          │
┌──────────────────────────▼──────────────────────┐
│  DOMAIN  (lib/domain/)                           │
│  Pure models. No Flutter, no Drift, no Riverpod. │
│  Task, Habit, Routine, Note, Mood. Everything    │
│  depends on these; these depend on nothing.      │
└─────────────────────────────────────────────────┘

  PLATFORM  (lib/platform/) — notifications, background
  scheduler, daily reset. Native-facing services.
```

### Why this way
- **Domain depends on nothing** → models are portable, testable, and can't be corrupted by framework churn.
- **Executive imports domain only** → the planning brain is deterministic and unit-testable in isolation. It literally cannot call AI or touch the database, because those aren't in its import graph.
- **Intelligence is a separate seam** → AI lives behind one interface (`PlanAdvisor`). This is the single most important boundary: it means AI can *enrich* a plan but never *become* it, and a broken/absent model degrades gracefully to a deterministic plan instead of breaking the app.
- **Presentation reads providers only** → no business logic in widgets, no direct DB access from UI. Swappable, testable.

---

## Folder structure

```
lib/
├── domain/              Pure models (no dependencies)
│   ├── task.dart        Task, EnergyLevel, TaskState (7-state living-state)
│   ├── habit.dart       Habit + streak logic
│   ├── routine.dart     Routine, RoutineStep, RoutineAnchor
│   ├── note.dart        Note + promote-to-task helpers
│   └── mood.dart        MoodLog, MoodLevel, triggersQuickWins
├── data/                Persistence (Drift) + repositories
│   ├── database.dart    7 tables, schema v3, migrations
│   ├── *_repository.dart       Interfaces
│   ├── *_repository_impl.dart   Drift implementations
│   └── *_seeds.dart     First-launch seed data
├── executive/
│   └── planner.dart     Executive engine + Plan + PlanAdvisor interface
├── intelligence/
│   ├── lexi_plan_advisor.dart   LexiPlanAdvisor, CloudGeminiPlanAdvisor
│   └── lexi_config.dart
├── app/
│   ├── providers.dart   Composition root — wires everything
│   ├── focus_timer.dart Global focus-timer Notifier
│   └── timeline.dart    Read-only TimelineEvent projection (DEC-004)
├── platform/
│   ├── notifications/notification_service.dart
│   ├── background/background_scheduler.dart
│   └── daily_reset.dart
├── presentation/
│   ├── app_shell.dart   4-tab bottom nav
│   ├── today_screen.dart        Next-best-action + focus timer
│   ├── notes_screen.dart
│   ├── reflect_screen.dart      Mood + week + habits
│   ├── routines_list_screen.dart
│   ├── routine_screen.dart      One-step runner + pace banner
│   ├── timeline_screen.dart     "Your Day" projection (built; not yet in nav)
│   ├── theme.dart       Design tokens
│   └── widgets/         Reusable: capture_sheet, energy_glyph,
│                        heartbeat_line, routine_pace_banner
└── main.dart            Init services, seed, launch AppShell

android/app/src/main/kotlin/com/neuroflow/
├── MainActivity.kt      Registers LexiBridge
└── lexi/LexiBridge.kt   Method channel stub for Gemini Nano
```

---

## Data flow — the core loop

The Today screen's plan is the heart of the app. Here's the actual flow:

```
Drift DB (Tasks table)
  └─> DriftTaskRepository.watchPending()   [Stream<List<Task>>]
        └─> pendingTasksProvider            [StreamProvider]
              └─> TodayController.build()    [AsyncNotifier<Plan>]
                    │
                    ├── reads todayMoodProvider (mood signal)
                    ├── reads interruptedTasksProvider (paused/blocked)
                    ├── Executive.evaluate(pending, mood:, interrupted:)  ← PURE, returns Plan
                    └── PlanAdvisor.refine(plan, pending)   ← AI seam, may enrich
                          └─> Plan
                                └─> todayControllerProvider
                                      └─> TodayScreen renders it
```

**Key insight:** the Executive produces a complete, correct plan *deterministically*. Mood is passed IN as data (so the Executive still does no I/O — determinism holds). The advisor's `refine()` may improve the plan but is wrapped so it can never throw or block — on any failure it returns the plan unchanged. The UI consumes the final `Plan` directly.

---

## Riverpod provider graph

**Infrastructure**
- `databaseProvider` → `AppDatabase` (Drift), disposed on teardown

**Repositories** (each wraps the DB)
- `taskRepositoryProvider`, `routineRepositoryProvider`, `habitRepositoryProvider`, `noteRepositoryProvider`, `moodRepositoryProvider`

**Reactive data streams**
- `pendingTasksProvider` → `Stream<List<Task>>` (not-started tasks)
- `completedTodayCountProvider` → `Stream<int>` (drives heartbeat)
- `interruptedTasksProvider` → `Stream<List<Task>>` (paused/blocked — Re-Entry source)
- `completedTodayProvider` → `Stream<List<Task>>` (completed today — feeds the timeline)
- `activeHabitsProvider`, `activeRoutinesProvider`, `activeNotesProvider`
- `dueRoutinesProvider` → `Future<List<Routine>>` (anchor-window match)
- `todayMoodProvider` → `Stream<MoodLog?>` (Quick Wins signal)
- `recentMoodsProvider` → `Stream<List<MoodLog>>` (week strip)

**Executive + AI**
- `executiveProvider` → `Executive` (pure engine)
- `advisorTierProvider` → `StateProvider<AdvisorTier>` (none/lexi/cloud)
- `planAdvisorProvider` → `PlanAdvisor` (resolves tier to advisor)

**Controllers**
- `todayControllerProvider` → `AsyncNotifierProvider<TodayController, Plan>`
- `focusTimerProvider` → `NotifierProvider<FocusTimerController, FocusState>`

---

## Drift schema (v3)

Seven typed tables. **Each entity is its own table with its own fields — this is intentional and must not be collapsed into a generic event model.**

| Table | Purpose | Notable columns |
|---|---|---|
| `Tasks` | To-do items | energy, status (`TaskState` key), dueDate, isQuickWin, estimatedMinutes, completedAt, **pausedAt / pausedStep / pausedNote** (v3 living-state) |
| `Habits` | Recurring intentions | frequency, isActive |
| `HabitCheckIns` | Habit completions | habitId, date, completed |
| `Routines` | Anchor sequences | anchor, scheduleHour/Minute, **activeDays** (v2), isActive |
| `RoutineSteps` | Steps within a routine | routineId, position, durationMinutes, isComplete |
| `Notes` | Quick capture | body, pinned, linkedTaskId |
| `MoodLogs` | Mood check-ins | level (1–5), loggedAt — **NO sync columns, on-device only** |

**Schema version: 3.** Migrations run via `MigrationStrategy.onUpgrade`, all data-preserving:
- **v1→v2** adds `Routines.activeDays` (nullable text; null = every day).
- **v2→v3** adds the three `Tasks` pause columns (`pausedAt`, `pausedStep`, `pausedNote`) and rewrites legacy status strings into `TaskState` keys (`pending→not_started`, `completed→complete`, `skipped→blocked`).

**Generated code:** `database.g.dart` is produced by `dart run build_runner build`. It is gitignored and MUST be regenerated after any schema change.

---

## Executive Function design notes — how the architecture serves the ADHD philosophy

This is the part that makes the layering *matter* rather than being architecture for its own sake:

- **ANCHORS + FLEX maps to the schema.** Anchors = Routines with `scheduleHour`/`activeDays` (fixed pins). Flex = Tasks (float in the gaps). The distinction is structural, not cosmetic.

- **"Moment of return" is why the Executive is deterministic.** An ADHD user returning to the app must get a *stable, predictable* plan — not a different suggestion every refresh. Determinism isn't an engineering nicety here; it's a UX requirement. Same state → same plan → trustable.

- **Quick Wins (mood-triggered mode swap) protects bad days.** `MoodLevel.triggersQuickWins` (≤ Low) makes `Executive.evaluate` reshape the day into ≤3 gentle tasks. The logic lives in the pure engine, driven by a signal passed in — the UI never decides this, preventing inconsistency.

- **The AI seam prevents dependency on AI.** An executive-function prosthetic cannot break because a model is slow or unavailable. `NoOpPlanAdvisor` is the default; the app is fully functional with zero AI. AI is strictly additive.

- **The focus timer's kind overtime** (amber, "still yours" copy, never red/punishing) is the "no shame mechanics" rule expressed in code. Contrast with the *routine pace banner*, which for hard-deadline routines (work morning) is deliberately more urgent — because a 6 AM clock-in genuinely needs "you're behind," where laundry does not. Same timing primitive, two tones, correct for each context.

- **Local-first = the app works in the user's real life.** Field work, dead zones, no signal — the app is the source of truth and never waits on a network. Google is a mirror, never a master.
