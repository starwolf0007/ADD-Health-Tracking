# Android Project Setup — Wear OS Integration
# One-time steps needed to wire the wear/ module into the Flutter project.
# Do these when you're home, before first compile of the watch code.

---

## 1. android/settings.gradle — add wear module

Add this line at the bottom:

```groovy
include ':wear'
project(':wear').projectDir = new File('../wear')
```

---

## 2. android/app/build.gradle — add wearable dependency

Inside `dependencies { }`:

```groovy
// Wearable Data Layer — shared with wear module
implementation 'com.google.android.gms:play-services-wearable:18.2.0'
```

Also add to `android { }` block if not already present:

```groovy
buildFeatures {
    viewBinding true
}
```

---

## 3. android/app/src/main/AndroidManifest.xml — register phone-side service

Inside `<application>`:

```xml
<!-- Receives Complete/Snooze messages from Pixel Watch 4 -->
<service
    android:name=".WearPhoneMessageReceiver"
    android:exported="true">
    <intent-filter>
        <action android:name="com.google.android.gms.wearable.MESSAGE_RECEIVED" />
        <data
            android:scheme="wear"
            android:host="*"
            android:pathPrefix="/neuroflow" />
    </intent-filter>
</service>
```

---

## 4. android/app/src/main/kotlin/dev/neuroflow/MainActivity.kt

Replace (or update) your existing `MainActivity.kt`:

```kotlin
package dev.neuroflow

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Wire the Wear OS bridge — Data Layer push + watch message listener.
        WearBridge.register(flutterEngine.dartExecutor.binaryMessenger, this)
        // Wire the alarm bridge — exact alarm scheduling from Flutter.
        AlarmBridge.register(flutterEngine.dartExecutor.binaryMessenger, this)
    }
}
```

---

## 5. Verify wear/build.gradle is included

The `wear/build.gradle` file is already written. Just confirm `settings.gradle`
includes `:wear` (step 1 above) and Android Studio will pick it up on next sync.

---

## 6. Gradle sync & build

In Android Studio (or terminal):

```bash
./gradlew :wear:assembleDebug    # build watch APK
./gradlew :app:assembleDebug     # build phone APK
```

Deploy phone APK to Pixel 10 Pro XL, wear APK to Pixel Watch 4 via ADB:

```bash
adb -s <phone_serial>  install build/outputs/apk/debug/app-debug.apk
adb -s <watch_serial>  install wear/build/outputs/apk/debug/wear-debug.apk
```

Pair the watch to the phone via the Wear OS app first if not already done.

---

## Notes

- `play-services-wearable:18.2.0` must be in BOTH `:app` and `:wear` build.gradle.
  The `:wear` version is already there. Step 2 adds it to `:app`.
- The `neuroflow/wear` MethodChannel is registered in `WearBridge.register()` —
  no changes needed to `pubspec.yaml` or any Flutter plugin.
- Tile preview drawable (`@drawable/tile_preview`) is referenced in the manifest.
  Add a placeholder PNG at `wear/src/main/res/drawable/tile_preview.png` to
  prevent a build warning. Any 384×384 dark image works for dev.
