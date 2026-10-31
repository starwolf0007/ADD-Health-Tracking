# Changelog

All notable changes to NeuroFlow will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased] - 2026-10-31

### Added

#### 1. ADHD Time-Blindness Visual Clock Timer (`src/components/VisualClockTimer.tsx`)
- **Analog Clock Face**: 60-minute circular dial with major tick marks and numbers (0, 5, 10... 55, 60).
- **Physical Moving Disk & Sweeping Hand**:
  - Colored sector recedes clockwise as time elapses, providing physical spatial awareness of time.
  - Sweeping hand indicates active minute position in real time.
- **Three Core Presets**:
  - `5 min`: Micro-sprint / inertia-breaker.
  - `25 min`: Standard Pomodoro focus block.
  - `50 min`: Deep work immersion block.
- **Dual Visual Tracking**:
  - Displays remaining time on the receding disk.
  - Displays actual time spent on task (`Actually spent on task: Xm Ys`) with a subtle ghost track.
- **Sensory-Friendly Audio & Pacing**:
  - Gentle Web Audio harmonic chime on completion (calm triad: E5, G#5, B5).
  - Optional soft auditory ticking toggle for body doubling and pacing.
- **Non-Jarring Overtime Flow**:
  - When reaching zero, transitions into a gold **Bonus Flow** mode (`+01:23`) to avoid disrupting hyperfocus.
- **Integration**:
  - Header "Timer" quick launcher in `AppShell`.
  - Today screen quick-bar with `5m`, `25m`, and `50m` preset pills.
  - "Clock" button on the Active Recommended Task card.

#### 2. Lexi AI Executive Function Coaching Interface (`src/components/LexiChatInterface.tsx`)
- **First-Class AppShell Tab**: Dedicated **Lexi AI** bottom navigation tab with glowing purple sparkle badge (`#BB86FC`).
- **Pre-Configured Executive Function Prompt Presets**:
  - *Break down a big task* (uses `gemini-4-argon` to deconstruct overwhelming projects into ≤2 min micro-steps).
  - *Break task paralysis* (sensory-friendly immediate initiation action).
  - *Low energy pivot* (reorganize day without shame for low-spoon days).
  - *Quiet spaces nearby* (Google Maps Grounding).
  - *ADHD research* (Google Search Grounding).
- **Interactive Action Steps**:
  - One-tap **"Add this step to Today"** button inserts broken-down steps directly into Today's schedule.
  - Contextual proposals for starting or pausing active tasks with return point notes.

#### 3. Real-Time Voice Conversations (`gemini-3.8-live`)
- **Full-Screen Voice Mode (`src/screens/LiveVoiceScreen.tsx`)**:
  - Server-side WebSocket streaming at `/api/live-ws` with `gemini-3.8-live` and Zephyr voice.
  - 16kHz microphone PCM audio capture and 24kHz gapless playback.
  - Animated pulsing audio visualizer.
  - Real-time spoken subtitle transcriptions (user input and Lexi output).
  - Live interruption detection and handling.

#### 4. Grounding with Google Search & Maps (`gemini-3.8-flash`)
- **Google Search Grounding**:
  - Endpoint `POST /api/gemini/search` equipped with `{ googleSearch: {} }`.
  - Extracts and displays verified web sources and citation links in chat.
- **Google Maps Grounding**:
  - Endpoint `POST /api/gemini/maps` equipped with `{ googleMaps: {} }` and geolocation support.
  - Recommends quiet cafes, libraries, gyms, and sensory-friendly workspaces with direct Google Maps links.

#### 5. Audio Transcription (`gemini-3.5-transcribe`)
- **Speech-to-Text Hook (`src/lib/useTranscribe.ts`)**:
  - Server endpoint `POST /api/gemini/transcribe`.
  - Microphone dictation button in the Quick Capture Sheet for hands-free task entry.
  - Microphone dictation button in the Lexi Chat input bar.

#### 6. Firebase Authentication & Cloud Firestore Persistence
- **Google Sign-In**: Integrated via Firebase Auth (`src/lib/firebase.tsx`) with guest fallback.
- **Cloud Firestore**:
  - Provisioned database (`ai-studio-addhealthtrackin-2d42f09e-2429-4958-8bf3-d2ee7b9ac637`).
  - Deployed `firestore.rules` and `firebase-blueprint.json` schema.
  - Two-way real-time sync for tasks, notes, routines, habits, and user settings.
  - User profile badge and cloud sync indicator in the app header and Settings.

#### 7. Modern React + TypeScript Architecture
- Rewrote application from legacy Flutter codebase into a high-performance React SPA.
- Vite + Tailwind CSS design system adhering to the calm-functional specification (`#0C0C0D` background, `#161618` surface, `#2FB083` emerald accent, `#D9A441` attention, `#BB86FC` Lexi, `#FFD700` achievement).
- Full-stack Express server (`server.ts`) with WebSocket support and server-side Gemini SDK integration.
