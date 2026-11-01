# Implementation Plan: NeuroFlow Executive Function Suite & Automated Drive Backups

## 1. Architecture Blueprint & Domain Model

### 1.1 User Stories & Target Workflows
- **Overcoming Task Paralysis**: As a user with ADHD experiencing executive dysfunction or time blindness, I can open NeuroFlow, choose a task, and have Lexi deconstruct it into an absurdly small, ≤2-minute physical initiation step with one-tap addition to my Today schedule.
- **Proactive Body Doubling**: During work sprints, I can initiate a proactive body-doubling session with Lexi (via chat or live voice) who checks in with gentle pacing, helps me maintain focus, and offers frictionless re-entry whenever context switches happen.
- **Visual Spatial Pacing**: I can run the analog visual clock timer (5m / 25m / 50m) to physically observe remaining time recede and see actual time spent on my task, with non-punitive bonus flow overtime that protects hyperfocus.
- **Automated Cloud Backup & Persistence**: All tasks, routines, habits, and notes automatically sync to Firebase Firestore (`ai-studio-addhealthtrackin-2d42f09e-2429-4958-8bf3-d2ee7b9ac637`), with automated daily or on-demand timestamped backups exported to Google Drive.

### 1.2 System Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                       Client (React)                        │
│  ┌───────────────┐ ┌────────────────┐ ┌──────────────────┐  │
│  │ Today + Clock │ │ Lexi Coach     │ │ Google Drive Wksp│  │
│  │ Visual Timer  │ │ Body Doubler   │ │ Backup / Restore │  │
│  └───────┬───────┘ └───────┬────────┘ └────────┬─────────┘  │
└──────────┼─────────────────┼───────────────────┼────────────┘
           │                 │                   │
           ▼                 ▼                   ▼
┌──────────────────┐ ┌────────────────┐ ┌─────────────────────┐
│ Cloud Firestore  │ │ Server Proxy   │ │ Google Drive API    │
│ Real-time Sync   │ │ (Gemini APIs)  │ │ (OAuth Scopes)      │
└──────────────────┘ └────────────────┘ └─────────────────────┘
```

---

## 2. Component Architecture & User Experience

### 2.1 View Hierarchy
1. **Today Dashboard (`src/screens/TodayScreen.tsx`)**:
   - Header with Google profile status and Cloud sync indicator.
   - Calm look-ahead schedule summary.
   - **Visual Clock Timer Quick-Bar**: 5m micro-sprint, 25m pomodoro, and 50m deep immersion triggers.
   - **Active Task Card**: Next step recommendation with direct "Clock" timer and "Body Double" launchers.
   - Automatic Quick Wins mode-swap on low-energy days.
2. **Body Doubling & Executive Coaching (`src/components/LexiChatInterface.tsx` & `LiveVoiceScreen.tsx`)**:
   - Dedicated "Body Double" mode: periodic quiet check-ins ("Still working on Step 1?").
   - Frictionless micro-step generator using `gemini-4-argon` and `gemini-3.8-flash`.
   - Real-time spoken conversation over WebSocket via `gemini-3.8-live`.
   - Speech-to-text dictation via `gemini-3.5-transcribe`.
3. **Visual Clock Timer (`src/components/VisualClockTimer.tsx`)**:
   - Analog dial with 60-minute tick marks and numbers.
   - Colored sector that recedes clockwise as time elapses.
   - Sweeping second and minute hands.
   - Dual tracking: remaining minutes + actual minutes spent.
   - Gentle Web Audio harmonic chime on completion and auditory tick toggle.
   - Seamless Bonus Flow overtime mode.
4. **Google Drive & Data Management (`src/screens/GoogleDriveScreen.tsx`)**:
   - Live Google Drive file browser with search and web links.
   - Automated & manual JSON backup export.
   - Mandatory confirmation modal on file deletions.

---

## 3. Executive Function Suite Specification

### 3.1 Proactive Body Doubling Workflow
- **Initiation**: User taps "Start Body Doubling" on an active task.
- **Pacing**: Lexi sets an unobtrusive check-in interval (e.g. 10m / 25m).
- **Sensory Guidance**: Ambient audio chime or gentle visual pulse in the applet tab.
- **De-escalation**: If stuck, Lexi asks: *"What is the physical tool or browser tab you need open right now?"* and logs an immediate return point note.

### 3.2 Visual Pomodoro Clock Timer
- Three preset time anchors:
  - `5 minutes`: Inertia-breaker micro sprint.
  - `25 minutes`: Standard Pomodoro block.
  - `50 minutes`: Deep work block.
- Visual disk behavior:
  - Wedge angle $\alpha = (\text{remainingSeconds} / 3600) \times 360^\circ$.
  - Recedes clockwise toward 12 o'clock.
  - Changes from Emerald (`#2FB083`) to Amber (`#D9A441`) in the final 3 minutes.
  - Replaced by Gold (`#FFD700`) pulsing ring during Bonus Flow overtime.

---

## 4. Cloud Firestore & Automated Google Drive Backups

### 4.1 Persistence Layer
- **Firestore Collections**:
  - `users/{uid}/tasks`: User tasks, energy tags, status, and reentry notes.
  - `users/{uid}/routines`: Timed routine checklists.
  - `users/{uid}/habits`: 30-day rolling habit records.
  - `users/{uid}/notes`: Captured thought dumps.
  - `users/{uid}/settings`: User preferences.
- **Firestore Security Rules**:
  - Strict owner-only access: `request.auth != null && request.auth.uid == userId`.

### 4.2 Automated Google Drive Backups
- **OAuth Authentication**:
  - Uses client-side token management via `GoogleAuthProvider` with 13 authorized Drive scopes.
- **Automated Backup Trigger**:
  - Automatically exports a snapshot of all user collections to a structured `NeuroFlow-Backup-YYYY-MM-DD.json` file on Google Drive during session end or weekly schedule.
- **User Safety Safeguards**:
  - Explicit confirmation modal before any deletion from Google Drive.

---

## 5. Verification & Acceptance Criteria

1. **Executive Function Coaching**:
   - Task breakdown produces 3 discrete, ≤2-minute physical steps.
   - "Add this step to Today" button immediately inserts the task into Firestore.
2. **Visual Clock Timer**:
   - Colored wedge visibly animates and recedes clockwise as seconds tick.
   - Preset buttons (5m, 25m, 50m) dynamically resize the dial.
   - Reaching 0 transitions cleanly into Bonus Flow overtime with a gentle chime.
3. **Voice & Dictation**:
   - `gemini-3.8-live` streams real-time bidirectional audio on the Live Voice screen.
   - Microphone dictation in Quick Capture transcribes speech via `gemini-3.5-transcribe`.
4. **Google Drive Backup**:
   - One-tap "Backup to Drive" uploads a valid JSON snapshot to the user's Drive.
   - File browser displays existing Drive items with functional links.
