package com.example.calorie_app

import android.content.Intent
import android.content.ComponentName
import android.appwidget.AppWidgetManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var healthChannel: MethodChannel? = null
    private var pendingAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingAction = intent?.getStringExtra("widget_action")
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kayleo/home_widgets")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPin" -> {
                    val type = when (call.arguments as? String) {
                        "calories" -> CalorieWidget::class.java
                        "barcode" -> BarcodeWidget::class.java
                        "streak" -> StreakWidget::class.java
                        "rings" -> RingsWidget::class.java
                        else -> null
                    }
                    val manager = AppWidgetManager.getInstance(this)
                    result.success(type != null && Build.VERSION.SDK_INT >= 26 &&
                        manager.isRequestPinAppWidgetSupported &&
                        manager.requestPinAppWidget(ComponentName(this, type), null, null))
                }
                "getInitialAction" -> {
                    result.success(pendingAction)
                    pendingAction = null
                }
                "update" -> {
                    @Suppress("UNCHECKED_CAST")
                    val snapshot = call.arguments as? Map<String, Any> ?: emptyMap()
                    val editor = getSharedPreferences("kayleo_widget", MODE_PRIVATE).edit()
                    snapshot.forEach { (key, value) ->
                        when (value) {
                            is Boolean -> editor.putBoolean(key, value)
                            is Int -> editor.putInt(key, value)
                            is String -> editor.putString(key, value)
                        }
                    }
                    editor.apply()
                    KayleoWidgetProvider.refreshAll(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        healthChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kayleo/health")
        healthChannel?.setMethodCallHandler { call, result ->
            if (call.method == "openSettings") {
                try {
                    startActivity(Intent("android.health.connect.action.HEALTH_HOME_SETTINGS"))
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra("widget_action") ?: return
        pendingAction = action
        channel?.invokeMethod("onAction", action)
    }
}
