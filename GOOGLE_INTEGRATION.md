# NeuroFlow — Google Integration Guide

## 1. Overview
NeuroFlow integrates with the Google ecosystem to provide a seamless experience for ADHD users. This guide explains how to use the unified Google Foundation built in Sprint 1.

## 2. Core Components

### Authentication
Handled by `GoogleServiceManager`. Users can connect their Google Account in the **Connected Services** section of Settings.
- **Silent Sign-In:** Automatically restores session on app startup.
- **Account Switching:** Allows users to change the connected account.

### Permissions
Managed via `GooglePermissionManager`. Scopes are requested incrementally as specific services are enabled.
- Basic: `email`, `profile`, `openid`.
- Service-specific: `tasks`, `calendar.readonly`, `drive.file`.

### Synchronization
The `SyncEngine` handles background data mirroring.
- **Outbound:** Local changes are enqueued in the `SyncQueue` Drift table.
- **Inbound:** Future sprints will implement periodic pulling from Google APIs.

## 3. Implementation Order
1.  **Google Tasks:** Spine integration (2-way sync).
2.  **Google Calendar:** Event-driven routines and alarms-off detection.
3.  **Health Connect:** Correlating activity/sleep with focus levels.
4.  **Google Drive:** Encrypted database backups.
5.  **Gemini:** Enhanced AI planning context.
6.  **Gmail/Contacts:** Communication-based task suggestions.

## 4. Security
- Tokens are stored in the platform's secure enclave (Keychain/Keystore) via `FlutterSecureStorage`.
- OAuth secrets are never hardcoded.
- Logging of sensitive user data or tokens is strictly forbidden.
