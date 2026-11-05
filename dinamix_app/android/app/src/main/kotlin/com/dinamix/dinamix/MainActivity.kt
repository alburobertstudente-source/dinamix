package com.dinamix.dinamix

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var alerts: AlertChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = AlertChannel(applicationContext)
        alerts = channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dynamix/alert").setMethodCallHandler(channel)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dinamix/keep_alive")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "start" -> {
                        val intent = Intent(this, RecordingService::class.java)
                        intent.putExtra(RecordingService.EXTRA_TITLE, call.argument<String>("title"))
                        intent.putExtra(RecordingService.EXTRA_SENSORS_ONLY, call.argument<Boolean>("sensorsOnly") ?: false)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, RecordingService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        alerts?.stopAlarm()
        super.onDestroy()
    }
}
