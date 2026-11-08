package com.nisaesakina.app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val screenSecurityChannel = "nisa_e_sakina/screen_security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenSecurityChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "setScreenshotBlocked") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val blocked = call.arguments as? Boolean
                if (blocked == null) {
                    result.error("invalid_argument", "Expected a boolean value", null)
                    return@setMethodCallHandler
                }

                runOnUiThread {
                    if (blocked) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
            }
    }
}
