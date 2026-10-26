package com.example.calorie_app

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate
import java.util.Calendar

class MainActivity : FlutterFragmentActivity(), SensorEventListener {
    private var channel: MethodChannel? = null
    private var healthChannel: MethodChannel? = null
    private var pendingAction: String? = null
    private var sensorManager: SensorManager? = null
    private var stepCounterSensor: Sensor? = null
    private var stepDetectorSensor: Sensor? = null
    private var listeningSteps = false
    private var receivedCounterReading = false
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingStepWaiters = mutableListOf<() -> Unit>()

    companion object {
        private const val REQ_ACTIVITY_RECOGNITION = 9412
        private const val STEP_PREFS = "kayleo_step_sensor"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingAction = intent?.getStringExtra("widget_action")
        super.onCreate(savedInstanceState)
        initSensors()
    }

    override fun onResume() {
        super.onResume()
        if (hasSensorPermission()) {
            startStepListening()
        }
    }

    override fun onDestroy() {
        stopStepListening()
        super.onDestroy()
    }

    private fun initSensors() {
        val sm = getSystemService(Context.SENSOR_SERVICE) as? SensorManager ?: return
        sensorManager = sm
        stepCounterSensor = sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        stepDetectorSensor = sm.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        if (hasSensorPermission()) {
            startStepListening()
        }
    }

    private fun hasHardwareStepSensor(): Boolean {
        if (sensorManager == null) initSensors()
        return stepCounterSensor != null || stepDetectorSensor != null
    }

    private fun hasSensorPermission(): Boolean {
        if (!hasHardwareStepSensor()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACTIVITY_RECOGNITION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun startStepListening() {
        if (listeningSteps || !hasSensorPermission()) return
        val sm = sensorManager ?: return
        var registered = false
        stepCounterSensor?.let { sensor ->
            registered = sm.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI) || registered
        }
        if (stepCounterSensor == null) {
            stepDetectorSensor?.let { sensor ->
                registered = sm.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI) || registered
            }
        }
        listeningSteps = registered
    }

    private fun stopStepListening() {
        if (!listeningSteps) return
        sensorManager?.unregisterListener(this)
        listeningSteps = false
    }

    override fun onSensorChanged(event: SensorEvent?) {
        val ev = event ?: return
        val today = LocalDate.now().toString()
        when (ev.sensor.type) {
            Sensor.TYPE_STEP_COUNTER -> {
                val rawCounter = ev.values.firstOrNull()?.toInt() ?: return
                if (rawCounter < 0) return
                val todaySteps = recordCounterReading(rawCounter, today)
                receivedCounterReading = true
                flushStepWaiters()
                healthChannel?.invokeMethod("onStepsChanged", todaySteps)
            }
            Sensor.TYPE_STEP_DETECTOR -> {
                if (stepCounterSensor == null) {
                    val delta = ev.values.firstOrNull()?.toInt()?.coerceAtLeast(1) ?: 1
                    val prefs = getSharedPreferences(STEP_PREFS, MODE_PRIVATE)
                    val updated = prefs.getInt("steps_$today", 0) + delta
                    prefs.edit()
                        .putInt("steps_$today", updated)
                        .putString("last_date", today)
                        .apply()
                    receivedCounterReading = true
                    flushStepWaiters()
                    healthChannel?.invokeMethod("onStepsChanged", updated)
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun flushStepWaiters() {
        if (pendingStepWaiters.isEmpty()) return
        val waiters = ArrayList(pendingStepWaiters)
        pendingStepWaiters.clear()
        waiters.forEach { it.invoke() }
    }

    private fun recordCounterReading(rawCounter: Int, today: String): Int {
        val prefs = getSharedPreferences(STEP_PREFS, MODE_PRIVATE)
        val lastDate = prefs.getString("last_date", null)
        val lastCounter = prefs.getInt("last_counter", -1)
        val uptimeMs = SystemClock.elapsedRealtime()
        val nowMs = System.currentTimeMillis()
        val cal = Calendar.getInstance().apply {
            timeInMillis = nowMs
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val msSinceMidnight = (nowMs - cal.timeInMillis).coerceAtLeast(0L)

        val todaySteps: Int = when {
            lastDate == null || lastCounter < 0 -> {
                // First time initializing the hardware step counter on this device.
                val initial = if (uptimeMs <= msSinceMidnight) {
                    // Phone booted today, so 100% of rawCounter steps were taken today.
                    rawCounter
                } else {
                    // Phone booted before today. Estimate today's share of cumulative steps
                    // so the user immediately sees their steps walked earlier today.
                    val uptimeDays = (uptimeMs.toDouble() / 86_400_000.0).coerceAtLeast(1.0)
                    val fractionOfDay = (msSinceMidnight.toDouble() / 86_400_000.0).coerceIn(0.08, 1.0)
                    if (rawCounter <= 0) {
                        0
                    } else if (rawCounter <= 12000 && uptimeDays < 1.5) {
                        rawCounter
                    } else {
                        val avgDaily = rawCounter.toDouble() / uptimeDays
                        (avgDaily * fractionOfDay).toInt().coerceIn(1, minOf(rawCounter, 25000))
                    }
                }
                Log.i(
                    "FLUTTER_HEALTH",
                    "Hardware step counter initialized: raw=$rawCounter, initialToday=$initial, uptimeMs=$uptimeMs"
                )
                initial
            }
            lastDate == today -> {
                val existing = prefs.getInt("steps_$today", 0)
                val delta = if (rawCounter >= lastCounter) {
                    rawCounter - lastCounter
                } else {
                    // Device rebooted today; counter reset to 0 on boot.
                    rawCounter
                }
                existing + delta
            }
            else -> {
                // Day rolled over since last reading.
                if (uptimeMs <= msSinceMidnight) {
                    maxOf(prefs.getInt("steps_$today", 0), rawCounter)
                } else {
                    prefs.getInt("steps_$today", 0)
                }
            }
        }

        prefs.edit()
            .putInt("steps_$today", todaySteps)
            .putInt("last_counter", rawCounter)
            .putString("last_date", today)
            .apply()
        return todaySteps
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_ACTIVITY_RECOGNITION) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                startStepListening()
            }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
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
            when (call.method) {
                "openSettings" -> {
                    val intents = listOf(
                        Intent("android.health.connect.action.HEALTH_HOME_SETTINGS"),
                        Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"),
                        packageManager.getLaunchIntentForPackage("com.hihonor.health"),
                        packageManager.getLaunchIntentForPackage("com.sec.android.app.shealth"),
                        packageManager.getLaunchIntentForPackage("com.google.android.apps.fitness")
                    ).filterNotNull()
                    var opened = false
                    for (candidate in intents) {
                        try {
                            startActivity(candidate)
                            opened = true
                            break
                        } catch (_: Exception) {}
                    }
                    result.success(opened)
                }
                "hasSensorPermission" -> {
                    val granted = hasSensorPermission()
                    if (granted) startStepListening()
                    result.success(granted)
                }
                "requestSensorPermission" -> {
                    if (!hasHardwareStepSensor()) {
                        result.success(false)
                    } else if (hasSensorPermission()) {
                        startStepListening()
                        result.success(true)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        if (pendingPermissionResult != null) {
                            result.success(false)
                        } else {
                            pendingPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
                                REQ_ACTIVITY_RECOGNITION
                            )
                        }
                    } else {
                        startStepListening()
                        result.success(true)
                    }
                }
                "getDailySteps" -> {
                    val args = call.arguments as? Map<*, *>
                    val dateKey = (args?.get("date") as? String) ?: LocalDate.now().toString()
                    val isToday = (args?.get("isToday") as? Boolean) ?: (dateKey == LocalDate.now().toString())
                    val prefs = getSharedPreferences(STEP_PREFS, MODE_PRIVATE)
                    if (!isToday || !hasSensorPermission()) {
                        result.success(prefs.getInt("steps_$dateKey", 0))
                    } else {
                        startStepListening()
                        if (receivedCounterReading || stepCounterSensor == null) {
                            result.success(prefs.getInt("steps_$dateKey", 0))
                        } else {
                            var completed = false
                            val finish = {
                                if (!completed) {
                                    completed = true
                                    result.success(prefs.getInt("steps_$dateKey", 0))
                                }
                            }
                            pendingStepWaiters.add(finish)
                            mainHandler.postDelayed({
                                pendingStepWaiters.remove(finish)
                                finish()
                            }, 400L)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        KayleoWidgetProvider.refreshAll(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra("widget_action") ?: return
        pendingAction = action
        channel?.invokeMethod("onAction", action)
    }
}
