package com.neuroflow

import com.neuroflow.healthconnect.HealthConnectBridge
import com.neuroflow.lexi.LexiBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(LexiBridge())
        flutterEngine.plugins.add(HealthConnectBridge())
    }
}
