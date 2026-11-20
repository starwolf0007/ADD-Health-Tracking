# NeuroFlow

NeuroFlow is an executive-function and task management application designed for immediate capture, cognitive offloading, and friction-free task execution.

> Note: The previous Flutter/Dart codebase was removed. NeuroFlow is currently maintained as a local-first web application. The platform decision is React PWA first, with native Flutter deferred as a future option.

## Tech Stack
- Framework: React + TypeScript
- Build Tool: Vite
- Architecture: Progressive Web App (PWA)
- Target Device: Motorola Razr Fold 2026 (Responsive for both folded and unfolded states)

## Local Setup & Execution
Prerequisites: Node.js (v18+), npm. Installation: npm ci. Environment variables: create a .env file with VITE_FIREBASE_API_KEY, VITE_FIREBASE_AUTH_DOMAIN, VITE_FIREBASE_PROJECT_ID, VITE_FIREBASE_STORAGE_BUCKET, VITE_FIREBASE_MESSAGING_SENDER_ID, VITE_FIREBASE_APP_ID, and VITE_GEMINI_API_KEY. Development scripts: npm run dev (run locally), npm test (run tests), npm run build (build for production).

## Core Workflow (The 7-State Contract)
Captured, Clarified, Picked, Active, Paused, Resumed, Finished.

## Technical Constraints & Development Rules
- No active-memory timers: live tick timers (setInterval) are prohibited for core functionality. All time tracking must use absolute timestamp diffing persisted immediately to local storage.
- Local-first: core capture and timer features must function offline via PWA caching and local state persistence.
- Preview over promises: all pull requests must generate an isolated, access-controlled preview link via the CI/CD pipeline for verification before merging.

## Deployment
Code pushed to main triggers automated CI/CD checks. All active development occurs on designated feature branches (e.g. feat/slice-1-now-card-fast-capture) and is evaluated via preview links prior to Bryan's final merge authorization.
