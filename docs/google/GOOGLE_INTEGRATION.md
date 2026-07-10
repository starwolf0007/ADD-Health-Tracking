# NeuroFlow — Google Integration Guide

## 1. Overview
NeuroFlow integrates with the Google ecosystem to provide a seamless experience for ADHD users. This guide explains how to use the unified Google Foundation built in Sprint 1.

## 2. Core Principles
1.  **Local-First:** Google sync is a mirror, not the master. The app must work without a network or account.
2.  **Incremental Scopes:** Never request broad permissions at once. Ask for "Tasks" only when the user enables "Tasks".
3.  **Single Orchestrator:** All Google interactions MUST go through `GoogleServiceManager`.

## 3. Using the Foundation

### Authentication
User auth state is managed by Riverpod.
-   Watch `googleAccountProvider` for the current user.
-   Watch `googleConnectionStateProvider` for connection status.

### Accessing APIs
Do not create API clients manually. Use `GoogleApiFactory`:
```dart
final tasksApi = await ref.read(googleApiFactoryProvider).createTasksApi();
```
The factory will check for permissions and return `null` if the user hasn't authorized the necessary scopes.

### Synchronization
The `SyncEngine` handles background mirroring.
```dart
await ref.read(googleSyncEngineProvider).flush();
```
Local changes should be enqueued in the `SyncQueue` Drift table via repositories. The `SyncEngine` will process this queue periodically.

## 4. Implementation Order (Roadmap)
1.  **Google Tasks:** Spine integration (2-way sync). Mirrors the `Tasks` Drift table.
2.  **Google Calendar:** Critical for ADHD "alarms-off" logic on holidays and time-blocking.
3.  **Health Connect:** Correlating physical energy with mental focus productivity.
4.  **Google Drive:** Encrypted cloud backups of the local SQLite database.
5.  **Gemini AI:** Cloud-level reasoning for the `PlanAdvisor` once context is available.
6.  **Gmail/Contacts:** Communication shortcuts and task extraction from mail.

## 5. Security Checklist
-   [ ] No tokens or PII in logs.
-   [ ] Tokens only reside in `google_sign_in` internal memory or Platform Secure Enclave.
-   [ ] Scopes are requested only when needed.
