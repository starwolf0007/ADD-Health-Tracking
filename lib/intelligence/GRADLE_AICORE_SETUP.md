# Gradle Setup for AICore / Gemini Nano (Lexi Bridge)

This repo's `android/app/build.gradle` does not exist yet — `flutter create`
generates it. **After generation, apply exactly the dependency + SDK-version
additions below.** `LexiBridge.kt` will not compile without the dependency.

The `AndroidManifest.xml` `<uses-feature>` addition (§3 below) has **already
been applied** in this repo — see `android/app/src/main/AndroidManifest.xml`.
It's documented here too so the full picture travels with one file.

---

## 1. `android/app/build.gradle` — dependency

Inside the `dependencies { }` block:

```gradle
dependencies {
    // Google AI Edge SDK — on-device Gemini Nano via the AICore system service.
    // ⚠️ EXPERIMENTAL developer preview (Google's own wording: "not for
    // production usage at this time"). Pinned exactly — no caret/range.
    implementation("com.google.ai.edge.aicore:aicore:0.0.1-exp01")

    // Kotlin coroutines (withTimeout, CoroutineScope in LexiBridge).
    // Flutter's generated project usually has kotlinx-coroutines transitively
    // (WearBridge.kt already uses it); declare explicitly so the bridge never
    // depends on a transitive accident:
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
```

## 2. `android/app/build.gradle` — SDK versions (and WHY)

```gradle
android {
    defaultConfig {
        // minSdk 31: the AI Edge SDK's own minimum for dependency resolution.
        // Devices between API 31-33 will install fine and simply report
        // Lexi unavailable (LexiBridge gates at runtime on SDK_INT >= 34,
        // because the AICore SYSTEM SERVICE only exists on Android 14 QPR1+).
        // Two different numbers, two different jobs:
        //   compile/install floor = 31 (SDK requirement)
        //   runtime feature gate  = 34 (AICore service existence, in code)
        minSdk 31
    }
}
```

Do NOT raise minSdk to 34 — that would block installs on perfectly good
phones that simply won't have Lexi. The whole §14 architecture is "the app
is complete with Lexi absent."

## 3. `AndroidManifest.xml` — feature declaration (already applied)

Inside `<manifest>`, alongside the existing tags:

```xml
<!-- Declares interest in on-device AI without requiring it. required="false"
     keeps the app installable on every device; availability is checked at
     runtime in LexiBridge (prepareInferenceEngine success = available). -->
<uses-feature
    android:name="android.software.ai_capabilities"
    android:required="false" />
```

**No permissions are needed.** AICore has no runtime permission; model
downloads route through Google's Private Compute Services, not the app.

## 4. Device / runtime reality (set expectations before testing)

| Requirement | Value |
|---|---|
| OS | Android 14 QPR1+ (API 34) — gated in LexiBridge code |
| Hardware | Pixel 9-series and newer |
| Emulator | ❌ Not supported — physical device only |
| Model present | Gemini Nano must already be downloaded on-device (AICore manages this; the bridge deliberately never triggers a download itself) |
| AICore APK | Present and current (system-managed; visible in `adb shell cmd aicore status` on supported builds) |

**Expected behavior on non-qualifying devices:** `checkGeminiNanoAvailable`
returns `false`, `LexiPlanAdvisor` silently NoOps, the deterministic plan
renders exactly as before. Zero UI difference. That's the design, not a
failure.

## 5. Verify

Kotlin only compiles during a Gradle build — `flutter analyze` checks Dart
only:

```bash
flutter analyze              # Dart side: expect 0 errors
flutter build apk --debug    # compiles LexiBridge.kt against the AICore dep
```

On a supported device with the model present, the plan's reason line may
change to Lexi's suggestion within ~1-3s of opening Today. On everything
else: identical to today. Either outcome is correct.

## 6. If the exp SDK breaks on a future version bump

The dependency is pinned, so this only happens on a deliberate upgrade.
Blast radius is ONE file (`LexiBridge.kt`) — the Dart side and the whole app
degrade to NoOp automatically. Fix the Kotlin against the new API surface,
nothing else moves. This containment is exactly why the seam exists.
