# NeuroFlow — Build & Run Guide

## Before first `flutter run`

Drift generates `database.g.dart` via `build_runner`. Without it, the app won't compile.

### 1. Get packages

```powershell
cd path\to\neuroflow
flutter pub get
```

### 2. Generate Drift code

```powershell
dart run build_runner build --delete-conflicting-outputs
```

This creates `lib/data/database.g.dart`. Run this again any time you change the schema in `database.dart`.

### 3. Set up Android manifest

Copy `android/app/src/main/AndroidManifest.xml` from this repo into your Flutter project's `android/app/src/main/` folder. If Flutter already generated one there, merge the `<uses-permission>` tags and the `<service>` tag — don't overwrite the `<activity>` block.

### 4. Run on your Pixel

With your Pixel 10 Pro XL connected via USB and USB debugging enabled:

```powershell
flutter run
```

For release build (faster, no debug overlay):
```powershell
flutter run --release
```

---

## Common issues

**`database.g.dart` not found**  
Run step 2. This file is gitignored and must be generated locally.

**`MissingPluginException: No implementation found for method checkGeminiNanoAvailable`**  
Expected in Phase 1 — the Lexi platform channel is not yet wired to a native Android plugin. The app gracefully falls back to `NoOpPlanAdvisor`. Not a crash.

**Notifications permission dialog doesn't appear**  
The app requests `POST_NOTIFICATIONS` on first launch. If it was denied previously, go to: Settings → Apps → NeuroFlow → Notifications → Allow.

**`WorkManager` tasks not firing**  
WorkManager uses inexact timing and respects Doze mode. Tasks may fire up to 15 minutes late. In debug mode, flip `isInDebugMode: true` in `BackgroundScheduler.init()` and check logcat for WorkManager output.

---

## File that gets generated (do not edit manually)

- `lib/data/database.g.dart` — Drift query extensions, generated from `database.dart`

## Files to push to git after changes

All files in `lib/`, `android/app/src/main/AndroidManifest.xml`, `pubspec.yaml`.  
Never commit `database.g.dart` — it's in `.gitignore`.
