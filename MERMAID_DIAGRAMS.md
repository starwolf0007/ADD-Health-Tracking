# NeuroFlow — Mermaid Diagrams

*Accurate to the current codebase. Paste any block into a Mermaid renderer (or GitHub markdown) to visualize.*

---

## 1. Overall architecture (layers + dependencies)

```mermaid
graph TD
    subgraph Presentation["PRESENTATION (lib/presentation)"]
        Screens["Screens: Today, Notes,<br/>Reflect, Routines"]
        Widgets["Widgets: capture_sheet,<br/>energy_glyph, heartbeat,<br/>routine_pace_banner"]
        Theme["theme.dart (tokens)"]
    end

    subgraph App["APP / COMPOSITION (lib/app)"]
        Providers["providers.dart<br/>(composition root)"]
        FocusTimer["focus_timer.dart"]
    end

    subgraph Executive["EXECUTIVE (lib/executive)"]
        Planner["planner.dart<br/>Executive + Plan"]
    end

    subgraph Intelligence["INTELLIGENCE (lib/intelligence)"]
        Advisor["PlanAdvisor impls<br/>(Lexi, Cloud, NoOp)"]
    end

    subgraph Data["DATA (lib/data)"]
        Repos["Repositories<br/>(interfaces + Drift impls)"]
        DB["database.dart<br/>(7 tables)"]
    end

    subgraph Domain["DOMAIN (lib/domain)"]
        Models["Task, Habit, Routine,<br/>Note, Mood — pure models"]
    end

    subgraph Platform["PLATFORM (lib/platform)"]
        Notif["notification_service"]
        BG["background_scheduler"]
        Reset["daily_reset"]
    end

    Screens --> Providers
    Widgets --> Providers
    Screens --> Theme
    Providers --> Planner
    Providers --> Repos
    Providers --> Advisor
    Planner --> Models
    Advisor --> Models
    Repos --> DB
    Repos --> Models
    DB --> Models
    Providers --> FocusTimer

    style Domain fill:#1E7A5A,color:#fff
    style Executive fill:#2FB083,color:#000
    style Intelligence fill:#D9A441,color:#000
```

---

## 2. Riverpod provider graph

```mermaid
graph LR
    DB[databaseProvider]

    DB --> TR[taskRepositoryProvider]
    DB --> RR[routineRepositoryProvider]
    DB --> HR[habitRepositoryProvider]
    DB --> NR[noteRepositoryProvider]
    DB --> MR[moodRepositoryProvider]

    TR --> PT[pendingTasksProvider<br/>Stream]
    TR --> CT[completedTodayCountProvider<br/>Stream]
    HR --> AH[activeHabitsProvider<br/>Stream]
    RR --> DR[dueRoutinesProvider<br/>Future]
    RR --> AR[activeRoutinesProvider<br/>Stream]
    NR --> AN[activeNotesProvider<br/>Stream]
    MR --> TM[todayMoodProvider<br/>Stream]
    MR --> RM[recentMoodsProvider<br/>Stream]

    EX[executiveProvider]
    AT[advisorTierProvider<br/>State] --> PA[planAdvisorProvider]

    PT --> TC[todayControllerProvider<br/>AsyncNotifier Plan]
    TM --> TC
    EX --> TC
    PA --> TC

    FT[focusTimerProvider<br/>Notifier FocusState]

    style TC fill:#2FB083,color:#000
    style EX fill:#2FB083,color:#000
    style PA fill:#D9A441,color:#000
```

---

## 3. Drift database schema (v3)

```mermaid
erDiagram
    TASKS {
        text id PK
        text title
        text notes
        text energy "low|medium|high"
        text status "TaskState: not_started..complete"
        datetime createdAt
        datetime dueDate
        bool isQuickWin
        int estimatedMinutes
        datetime completedAt
        datetime pausedAt "v3 living-state"
        text pausedStep "v3 living-state"
        text pausedNote "v3 living-state"
    }
    HABITS {
        text id PK
        text name
        text notes
        text frequency
        bool isActive
        datetime createdAt
    }
    HABIT_CHECKINS {
        text id PK
        text habitId FK
        datetime date
        bool completed
        datetime createdAt
    }
    ROUTINES {
        text id PK
        text name
        text anchor
        int scheduleHour
        int scheduleMinute
        bool isActive
        text activeDays "v2: 12345=weekdays, null=daily"
        datetime createdAt
    }
    ROUTINE_STEPS {
        text id PK
        text routineId FK
        int position
        text title
        text notes
        int durationMinutes
        bool isComplete
    }
    NOTES {
        text id PK
        text body
        bool pinned
        text linkedTaskId
        datetime createdAt
        datetime updatedAt
    }
    MOODLOGS {
        text id PK
        int level "1-5, ON-DEVICE ONLY"
        text note
        datetime loggedAt
    }

    HABITS ||--o{ HABIT_CHECKINS : "has"
    ROUTINES ||--o{ ROUTINE_STEPS : "has"
```

---

## 4. Living-State Task flow (BUILT — Phase 2 Step 1)

*Shipped. This 7-state machine (`TaskState` in `lib/domain/task.dart`) replaced the old binary `TaskStatus {pending, completed, skipped}`. Transitions are guarded by `TaskState.allowedNext`; `Task.transitionTo()` keeps pause/complete metadata consistent.*

```mermaid
stateDiagram-v2
    [*] --> NotStarted
    NotStarted --> Preparing: begin setup
    NotStarted --> InProgress: just start
    Preparing --> InProgress: ready
    InProgress --> Paused: step away
    InProgress --> Blocked: hit a wall
    InProgress --> Checkpoint: safe stopping point
    Paused --> InProgress: resume (Re-Entry Card)
    Blocked --> InProgress: unblocked
    Checkpoint --> InProgress: continue
    Checkpoint --> Complete: finish
    InProgress --> Complete: done
    Complete --> [*]

    note right of Paused
        Re-Entry Card reads
        the stall point here
    end note
    note right of Checkpoint
        "Checkpoint" not
        "Micro-Complete" —
        a safe place to stop,
        not a partial failure
    end note
```

---

## 5. Today plan generation (the core loop, CURRENT)

```mermaid
sequenceDiagram
    participant DB as Drift DB
    participant Repo as TaskRepository
    participant PT as pendingTasksProvider
    participant TC as TodayController
    participant EX as Executive (pure)
    participant AD as PlanAdvisor
    participant UI as TodayScreen

    DB->>Repo: watchPending() stream
    Repo->>PT: List<Task>
    PT->>TC: build() triggered
    TC->>TC: read todayMoodProvider + interruptedTasksProvider
    TC->>EX: evaluate(pending, mood:, interrupted:)
    EX-->>TC: Plan (deterministic, incl. returnable)
    TC->>AD: refine(plan, pending)
    Note over AD: may enrich,<br/>never throws,<br/>NoOp by default
    AD-->>TC: Plan (final)
    TC->>UI: AsyncValue<Plan>
    UI->>UI: render primaryTask or quickWins

    Note over DB,UI: On markComplete, Drift re-emits →<br/>build() re-runs → UI updates
```

---

## 6. Timeline projection (BUILT — Phase 2 Step 2)

*Shipped as `lib/app/timeline.dart` (`timelineProvider`) + `timeline_screen.dart`. A read-only merge, NOT a storage table — nothing writes a TimelineEvent (DEC-004). Current merge inputs: interrupted tasks, completed tasks, mood check-ins, due routines. Focus sessions and voice captures (below) are future layers. The screen isn't wired into nav yet — see TECH_DEBT TD-11.*

```mermaid
graph TD
    T[Tasks table] --> M{Timeline Merge<br/>Provider<br/>READ-ONLY}
    R[Routines +<br/>completions] --> M
    MO[MoodLogs] --> M
    F[Focus sessions] --> M
    V[Voice captures<br/>future] --> M

    M --> TE["Stream of TimelineEvents<br/>presentation objects<br/>merged by timestamp"]
    TE --> UI[Your Day timeline UI]
    TE --> REC[Re-Entry Card<br/>reads stall point]

    style M fill:#2FB083,color:#000
    style TE fill:#D9A441,color:#000
```

> **The rule, restated:** `TimelineEvent` is assembled at READ time. The typed tables stay the source of truth. Nothing writes a TimelineEvent. *Present as events, persist as types.*
