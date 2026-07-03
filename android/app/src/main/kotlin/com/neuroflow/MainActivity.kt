// PLACEMENT NOTE: this file lands AFTER `flutter create --platforms=android .`
// generates the Android shell (COMPILE_PATH.md step 1). Put it in the package
// directory matching your applicationId in android/app/build.gradle — if the
// generated package differs from com.neuroflow, update the `package` line
// below to match. Without this registration, LexiBridge exists but is never
// attached to the engine, and every channel call throws
// MissingPluginException (which the Dart advisor catches -> permanent NoOp).

package com.neuroflow

import com.neuroflow.lexi.LexiBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(LexiBridge())
    }
}
