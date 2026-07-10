# NeuroFlow — Modernization Sprint Handover
**Date:** 2026-07-08  
**Sprint authority:** ADR-006 — Dependency Modernization Policy  
**Executor:** chief-operator  

---

## Summary

All five stages of the controlled dependency modernization sprint completed successfully. Every Green Gate passed. The APK compiles cleanly. No deprecated patterns remain in the codebase.

---

## Upgraded Versions

### Stage 3+2 — Riverpod 3.0 + Drift (combined)

Combined per ADR-006 exception: `riverpod_generator ^4.x` requires `source_gen ^3.x`, which conflicts with `drift_dev <2.28.2` requiring `source_gen ^2.x`. Resolved by upgrading both ecosystems together.

| Package | Was | Now (resolved) |
|---|---|---|
| `flutter_riverpod` | ^2.5.1 | ^3.0.0 → **3.1.0** |
| `riverpod_annotation` | ^2.3.5 | ^4.0.0 → **4.0.0** |
| `riverpod_generator` | ^2.6.5 | ^4.0.0 → **4.0.0+1** |
| `drift_dev` | >=2.18.0 <2.28.2 | >=2.28.2 → **2.28.3** |
| `build_runner` | >=2.4.0 <2.15.0 | >=2.15.0 → **2.15.1** |
| `source_gen` | 2.x (transitive) | **4.2.3** (transitive) |
| `analyzer` | 6.x (transitive) | **8.4.1** (transitive) |

### Stage 4 — Google Auth & API Modernization

| Package | Was | Now (resolved) |
|---|---|---|
| `google_sign_in` | ^6.2.1 | ^7.0.0 → **7.2.0** |
| `googleapis` | ^13.1.0 | ^16.0.0 → **16.0.0** |
| `http` | *(transitive)* | ^1.2.0 → **1.6.0** (promoted to direct) |
| `extension_google_sign_in_as_googleapis_auth` | 2.0.12 | **removed** |
| `googleapis_auth` | any | **removed** |

### Stage 5 — LexiBridge Optimization

No pubspec changes. Kotlin-only refactor. Verified via `flutter build apk --debug`.

---

## Deprecated Patterns Removed

### Riverpod 3.0 Breaking Changes

**`StateProvider` removed.** Replaced with `NotifierProvider` + an explicit notifier class exposing a `set()` method. The `state` setter is now internal-only in Riverpod 3.x.

| File | Old | New |
|---|---|---|
| `lib/app/achievements.dart` | `StateProvider<bool>` | `NotifierProvider<AchievementsEnabledNotifier, bool>` |
| `lib/app/providers.dart` | `StateProvider<AdvisorTier>` | `NotifierProvider<AdvisorTierNotifier, AdvisorTier>` |
| `lib/app/bootstrap.dart` | `.notifier.state = AdvisorTier.cloud` | `.notifier.set(AdvisorTier.cloud)` |
| `lib/presentation/settings_screen.dart` (×2) | `.notifier.state = …` | `.notifier.set(…)` |

**`AsyncValue.valueOrNull` renamed to `.value`.** Found in `lib/presentation/today_screen.dart` lines 91 and 107.

**`--delete-conflicting-outputs` flag removed** from `run_green_gate.ps1` — `build_runner 2.15.x` made it the default and removed the explicit flag.

### Google Sign-In 7.x Breaking Changes

The `google_sign_in` 7.x API is a complete redesign. All old patterns were replaced:

| Old (v6) | New (v7) |
|---|---|
| `GoogleSignIn(clientId: …, scopes: …)` constructor | `GoogleSignIn.instance` singleton + `initialize()` |
| `_googleSignIn.onCurrentUserChanged` stream | `GoogleSignIn.instance.authenticationEvents` stream (`GoogleSignInAuthenticationEvent`) |
| `_googleSignIn.currentUser` property | Internal `_currentUser` field, updated via event stream |
| `_googleSignIn.signIn()` | `GoogleSignIn.instance.authenticate()` |
| `_googleSignIn.signInSilently()` | `GoogleSignIn.instance.attemptLightweightAuthentication()` |
| `_googleSignIn.canAccessScopes(scopes)` | `authorizationClient.authorizationForScopes(scopes)` (null = not granted) |
| `_googleSignIn.requestScopes(scopes)` | `authorizationClient.authorizeScopes(scopes)` |
| `_googleSignIn.authenticatedClient()` (extension) | `_GoogleAuthClient extends http.BaseClient` + `account.authorizationClient.authorizationHeaders(scopes)` |
| `auth.AuthClient?` return type | `http.Client?` |

### Google Auth State Machine

`GoogleConnectionStatus` enum expanded from a 4-value boolean-style enum to a proper 5-state machine:

| Old | New |
|---|---|
| `notConnected` | `disconnected` |
| *(none)* | `connecting` |
| `connected` | `authenticated` |
| `expired` | `expired` |
| `error` | `failed` |

`isConnected` now checks `status == GoogleConnectionStatus.authenticated`.

`GoogleServiceManager` wires all transitions: `disconnected → connecting → authenticated/failed`, `refreshToken` transitions through `connecting → authenticated/expired`.

### LexiBridge Lifecycle

The old bridge handled every `generateResponse` call inline with no session management. The refactored bridge implements a proper **Initialize → Warm → Reuse Session → Dispose** lifecycle:

- `LifecycleState` enum (`UNINITIALIZED`, `INITIALIZING`, `WARMING`, `READY`, `DISPOSED`) guards all inference calls
- Session (`Any?`) allocated once during warm-up on `Dispatchers.IO`, reused for all subsequent inference calls
- `dispose()` tears down the session and cancels the coroutine scope in `onDetachedFromEngine`
- All real SDK calls are marked `// TODO [AICORE]:` — `com.google.ai.edge.aicore:aicore:0.0.1-exp01` is already on the classpath in `android/app/build.gradle.kts`

---

## Green Gate Results

| Stage | Step 1: pub get | Step 2: build_runner | Step 3 | Result |
|---|---|---|---|---|
| 3+2 (Riverpod + Drift) | ✅ exit 0 | ✅ 129 outputs, 31s | ✅ `flutter analyze`: No issues | **PASSED** |
| 4 (Google Auth) | ✅ exit 0 | ✅ 129 outputs, 54s | ✅ `flutter analyze`: No issues | **PASSED** |
| 5 (LexiBridge) | ✅ exit 0 | ✅ 129 outputs, 28s | ✅ `flutter build apk --debug`: 90.9s | **PASSED** |

---

## Non-Blocking Warnings (no action required)

- **`SDK language version 3.12.0 > analyzer 3.11.0`** — build_runner warning; resolves naturally when `analyzer` catches up to SDK. Does not affect output.
- **`workmanager_android` KGP warning** — third-party plugin applies the Kotlin Gradle Plugin directly; flagged by Flutter tooling. Not our code. File an issue with the `workmanager` package if it persists after their next release.
- **`java.lang.System::load` restricted method** — Gradle 9.x / JVM internals warning from the Gradle wrapper. Not actionable.
- **39 packages have newer versions incompatible with dependency constraints** — expected; these are held back by peer constraints. Run `dart pub outdated` to review when planning the next sprint.

---

## What Comes Next

- **GitHub push** — Bryan pushes all changes manually (credentials constraint; tokens must not appear in chat logs).
- **Gemini Nano wiring** — When `aicore` API stabilises, drop real calls into the `// TODO [AICORE]:` anchors in `LexiBridge.kt`. The lifecycle scaffolding is production-ready.
- **Scope pre-authorization UI** — `GooglePermissionManager.requestScopes()` now calls `authorizeScopes()` which requires a user interaction gesture on Android. Ensure any scope request is triggered from a button tap, not a background context.
- **`@riverpod` annotation migration** (Stage 3 stretch goal from the sprint doc) — providers still use manual `NotifierProvider` definitions. A follow-on sprint can convert them to `@riverpod` annotation style once the team is ready.
