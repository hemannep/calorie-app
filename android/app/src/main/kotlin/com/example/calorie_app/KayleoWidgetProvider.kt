package com.example.calorie_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import kotlin.math.min
import android.widget.RemoteViews
import java.text.NumberFormat
import java.time.LocalDate
import java.time.DayOfWeek
import java.time.temporal.ChronoUnit
import kotlin.math.max

open class KayleoWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "com.example.calorie_app.TOGGLE_CALORIES") {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
            if (id >= 0) {
                val prefs = context.getSharedPreferences("kayleo_widget", Context.MODE_PRIVATE)
                val key = "consumed_$id"
                prefs.edit().putBoolean(key, !prefs.getBoolean(key, false)).apply()
                update(context, AppWidgetManager.getInstance(context), id)
            }
            return
        }
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_DATE_CHANGED) refreshAll(context)
    }

    private fun update(context: Context, manager: AppWidgetManager, id: Int) {
        val prefs = context.getSharedPreferences("kayleo_widget", Context.MODE_PRIVATE)
        val ready = prefs.getBoolean("ready", false)
        val savedDate = runCatching { LocalDate.parse(prefs.getString("date", "")) }.getOrNull()
        val daysOld = savedDate?.let { ChronoUnit.DAYS.between(it, LocalDate.now()) } ?: 999L
        val current = ready && daysOld == 0L
        val calories = if (current) prefs.getInt("calories", 0) else 0
        val calorieTarget = if (ready) prefs.getInt("calorieTarget", 0) else 0
        val consumed = prefs.getBoolean("consumed_$id", false)
        val displayed = if (consumed) calories else kotlin.math.abs(calorieTarget - calories)
        val calorieCaption = if (consumed) "Calories consumed" else if (calories > calorieTarget) "Calories over" else "Calories left"
        val loggedToday = current && prefs.getBoolean("loggedToday", false)
        val streak = when {
            !ready -> 0
            daysOld == 0L -> prefs.getInt("streak", 0)
            daysOld == 1L && prefs.getBoolean("loggedToday", false) -> prefs.getInt("streak", 0)
            else -> 0
        }
        val layout = when (this) {
            is StreakWidget -> R.layout.widget_streak_premium
            is RingsWidget -> R.layout.widget_rings
            is BarcodeWidget -> R.layout.widget_barcode
            else -> R.layout.widget_calories
        }
        val views = RemoteViews(context.packageName, layout)
        applyAppearance(context, views, prefs.getString("appearance", "system") ?: "system")
        when (this) {
            is StreakWidget -> {
                val systemDark = (context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES
                val appearance = prefs.getString("appearance", "system")
                val dark = appearance == "dark" || (appearance == "system" && systemDark)
                views.setImageViewBitmap(R.id.streak_art, streakArtwork(streak, dark))
                views.setContentDescription(R.id.streak_art, "Kayleo: $streak day meal logging streak. Tap to view progress.")
                views.setTextViewText(R.id.streak_value, "$streak")
                views.setTextViewText(R.id.streak_hint, when {
                    !ready -> "Open Kayleo to begin"
                    loggedToday -> "Logged today · well done"
                    streak == 0 -> "Log a meal to start"
                    else -> "Log today to continue"
                })
                val sameWeek = savedDate?.with(DayOfWeek.MONDAY) == LocalDate.now().with(DayOfWeek.MONDAY)
                val week = if (ready && sameWeek) prefs.getString("weekLogged", "0000000") ?: "0000000" else "0000000"
                val weekIds = intArrayOf(R.id.week_mon, R.id.week_tue, R.id.week_wed, R.id.week_thu, R.id.week_fri, R.id.week_sat, R.id.week_sun)
                weekIds.forEachIndexed { index, viewId ->
                    val done = week.getOrNull(index) == '1'
                    views.setInt(viewId, "setBackgroundResource", if (done) R.drawable.widget_week_done else R.drawable.widget_week_dot)
                    views.setTextColor(viewId, if (done) Color.WHITE else Color.rgb(98, 110, 100))
                }
                views.setOnClickPendingIntent(R.id.widget_root, action(context, "streak"))
            }
            is BarcodeWidget -> {
                views.setOnClickPendingIntent(R.id.widget_root, action(context, "barcode"))
                views.setOnClickPendingIntent(R.id.barcode_button, action(context, "barcode"))
            }
            is RingsWidget -> {
                views.setTextViewText(R.id.rings_calories, if (ready) format(displayed) else "—")
                views.setTextViewText(R.id.rings_target, if (ready) calorieCaption else "Open Kayleo")
                views.setImageViewBitmap(R.id.calorie_ring, ring(240, calories, calorieTarget, ACCENT, segmented = true))
                views.setContentDescription(R.id.calorie_ring, "$calories of $calorieTarget calories")
                val macroKeys = arrayOf("protein", "carbs", "fat")
                val macroTargetKeys = arrayOf("proteinTarget", "carbTarget", "fatTarget")
                val macroColors = intArrayOf(Color.rgb(240, 120, 148), Color.rgb(241, 185, 99), Color.rgb(154, 125, 221))
                val imageIds = intArrayOf(R.id.protein_ring, R.id.carbs_ring, R.id.fat_ring)
                val labelIds = intArrayOf(R.id.protein_label, R.id.carbs_label, R.id.fat_label)
                val titles = arrayOf("Protein", "Carbs", "Fat")
                val textIds = intArrayOf(R.id.protein_value, R.id.carbs_value, R.id.fat_value)
                macroKeys.forEachIndexed { index, key ->
                    val amount = if (current) prefs.getInt(key, 0) else 0
                    val target = if (ready) prefs.getInt(macroTargetKeys[index], 0) else 0
                    views.setImageViewBitmap(imageIds[index], ring(68, amount, target, macroColors[index]))
                    views.setTextViewText(textIds[index], if (ready) "${kotlin.math.abs(target - amount)}g" else "—")
                    views.setTextViewText(labelIds[index], "${titles[index]} ${if (amount > target) "over" else "left"}")
                    views.setContentDescription(imageIds[index], "$key: $amount of $target grams")
                }
                views.setOnClickPendingIntent(R.id.widget_root, action(context, "today"))
                views.setOnClickPendingIntent(R.id.rings_scan, action(context, "photo"))
                views.setOnClickPendingIntent(R.id.rings_barcode, action(context, "barcode"))
                views.setOnClickPendingIntent(R.id.rings_voice, action(context, "voice"))
            }
            else -> {
                views.setTextViewText(R.id.calorie_value, if (ready) format(displayed) else "—")
                views.setTextViewText(R.id.calorie_target, if (ready) calorieCaption else "Open Kayleo")
                views.setImageViewBitmap(R.id.calorie_ring, ring(240, calories, calorieTarget, ACCENT, segmented = true))
                views.setContentDescription(R.id.calorie_ring, "$calories of $calorieTarget calories")
                views.setOnClickPendingIntent(R.id.widget_root, action(context, "today"))
                views.setOnClickPendingIntent(R.id.log_food_button, action(context, "photo"))
            }
        }
        if (this is CalorieWidget || this is RingsWidget) {
            val toggle = Intent(context, javaClass).setAction("com.example.calorie_app.TOGGLE_CALORIES")
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            views.setOnClickPendingIntent(R.id.calorie_display, PendingIntent.getBroadcast(context, id, toggle,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            views.setContentDescription(R.id.calorie_display, "$displayed $calorieCaption. Tap to switch display.")
            if (this is RingsWidget) {
                val width = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 300)
                views.setTextViewTextSize(R.id.rings_calories, TypedValue.COMPLEX_UNIT_SP, if (width < 290) 22f else 28f)
            }
        }
        manager.updateAppWidget(id, views)
    }

    companion object {
        private val ACCENT = Color.rgb(22, 62, 45)

        private fun format(value: Int) = NumberFormat.getIntegerInstance().format(value)

        private fun streakArtwork(streak: Int, dark: Boolean): Bitmap {
            val bitmap = Bitmap.createBitmap(600, 600, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val background = if (dark) Color.rgb(29, 27, 36) else Color.rgb(252, 250, 244)
            paint.color = background
            canvas.drawRoundRect(RectF(0f, 0f, 600f, 600f), 64f, 64f, paint)
            fun flame(data: String, top: Int, bottom: Int) {
                paint.style = Paint.Style.FILL
                paint.shader = android.graphics.LinearGradient(0f, 80f, 0f, 440f, top, bottom, android.graphics.Shader.TileMode.CLAMP)
                canvas.drawPath(androidx.core.graphics.PathParser.createPathFromPathData(data)!!, paint)
                paint.shader = null
            }
            flame("M284,84 C350,108 380,166 370,215 C398,198 403,173 400,156 C461,219 469,302 429,361 C401,407 347,432 293,422 C217,418 168,363 174,296 C178,250 201,218 224,190 C217,229 235,237 246,244 C276,193 301,143 284,84 Z", Color.rgb(255, 181, 48), Color.rgb(239, 128, 68))
            flame("M305,225 C332,253 337,273 331,292 C350,282 359,270 359,258 C392,301 385,355 354,377 C322,398 276,394 253,363 C225,326 252,290 274,272 C271,294 278,305 287,310 C303,281 312,257 305,225 Z", Color.rgb(255, 238, 164), Color.rgb(255, 204, 111))
            paint.color = Color.rgb(255, 214, 150)
            fun star(x: Float, y: Float, radius: Float) {
                val path = android.graphics.Path()
                path.moveTo(x, y-radius); path.lineTo(x+radius*.3f,y-radius*.3f)
                path.lineTo(x+radius,y); path.lineTo(x+radius*.3f,y+radius*.3f)
                path.lineTo(x,y+radius); path.lineTo(x-radius*.3f,y+radius*.3f)
                path.lineTo(x-radius,y); path.lineTo(x-radius*.3f,y-radius*.3f); path.close()
                canvas.drawPath(path,paint)
            }
            star(124f,161f,26f); star(466f,117f,32f); star(119f,289f,12f)
            paint.typeface = android.graphics.Typeface.create("sans-serif-condensed", android.graphics.Typeface.BOLD)
            paint.textAlign = Paint.Align.CENTER
            paint.textSize = if (streak < 100) 204f else 156f
            paint.style = Paint.Style.STROKE
            paint.strokeJoin = Paint.Join.ROUND
            paint.strokeWidth = 22f
            paint.color = background
            canvas.drawText("$streak",300f,493f,paint)
            paint.strokeWidth = 10f
            paint.color = Color.rgb(239, 171, 119)
            canvas.drawText("$streak",300f,493f,paint)
            paint.style = Paint.Style.FILL
            paint.color = background
            canvas.drawText("$streak",300f,493f,paint)
            paint.typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD)
            paint.textSize = 23f
            paint.color = if (dark) Color.rgb(222, 209, 194) else Color.rgb(91, 79, 66)
            canvas.drawText("Kayleo",300f,558f,paint)
            return bitmap
        }

        private fun applyAppearance(context: Context, views: RemoteViews, preference: String) {
            val systemDark = (context.resources.configuration.uiMode and
                android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES
            val dark = preference == "dark" || (preference == "system" && systemDark)
            val text = if (dark) Color.rgb(245, 247, 241) else Color.rgb(22, 62, 45)
            val muted = if (dark) Color.rgb(181, 193, 183) else Color.rgb(98, 110, 100)
            val background = if (dark) R.drawable.widget_card_dark else R.drawable.widget_card
            val button = if (dark) R.drawable.widget_button_dark else R.drawable.widget_button
            val tile = if (dark) R.drawable.widget_action_tile_dark else R.drawable.widget_action_tile
            views.setInt(R.id.widget_root, "setBackgroundResource", background)
            views.setTextColor(R.id.rings_brand, text)
            views.setTextColor(R.id.rings_day, muted)
            listOf(R.id.log_food_button, R.id.barcode_button).forEach { id ->
                runCatching { views.setInt(id, "setBackgroundResource", button) }
            }
            listOf(R.id.rings_scan, R.id.rings_barcode, R.id.rings_voice).forEach { id ->
                runCatching { views.setInt(id, "setBackgroundResource", tile) }
            }
            views.setImageViewResource(R.id.rings_camera_icon, if (dark) R.drawable.widget_camera_dark_icon else R.drawable.widget_camera_light_icon)
            views.setImageViewResource(R.id.rings_barcode_icon, if (dark) R.drawable.widget_barcode_dark_icon else R.drawable.widget_barcode_icon)
            views.setImageViewResource(R.id.rings_mic_icon, if (dark) R.drawable.widget_mic_dark_icon else R.drawable.widget_mic_icon)
            if (dark) {
                runCatching { views.setImageViewResource(R.id.calorie_camera_icon, R.drawable.widget_camera_dark_icon) }
                runCatching { views.setImageViewResource(R.id.rings_camera_icon, R.drawable.widget_camera_dark_icon) }
                runCatching { views.setImageViewResource(R.id.rings_barcode_icon, R.drawable.widget_barcode_dark_icon) }
                runCatching { views.setImageViewResource(R.id.rings_mic_icon, R.drawable.widget_mic_dark_icon) }
                runCatching { views.setImageViewResource(R.id.barcode_icon, R.drawable.widget_barcode_dark_icon) }
            }
            listOf(
                R.id.calorie_value, R.id.rings_calories, R.id.protein_value,
                R.id.carbs_value, R.id.fat_value,
            ).forEach { id -> runCatching { views.setTextColor(id, text) } }
            listOf(R.id.calorie_target, R.id.rings_target, R.id.streak_hint).forEach { id ->
                runCatching { views.setTextColor(id, muted) }
            }
            runCatching { views.setTextColor(R.id.streak_value, Color.rgb(111, 53, 29)) }
            runCatching { views.setTextColor(R.id.streak_caption, text) }
            runCatching { views.setTextColor(R.id.streak_brand, if (dark) Color.rgb(184, 227, 107) else text) }
            runCatching { views.setTextColor(R.id.streak_title, muted) }
        }

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            listOf(CalorieWidget::class.java, StreakWidget::class.java, RingsWidget::class.java, BarcodeWidget::class.java).forEach { type ->
                val ids = manager.getAppWidgetIds(ComponentName(context, type))
                if (ids.isNotEmpty()) {
                    val intent = Intent(context, type).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    context.sendBroadcast(intent)
                }
            }
        }

        private fun action(context: Context, value: String): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                data = Uri.parse("kayleo://widget/$value")
                putExtra("widget_action", value)
            }
            return PendingIntent.getActivity(context, value.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        private fun ring(size: Int, amount: Int, target: Int, color: Int, segmented: Boolean = false): Bitmap {
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = size * if (segmented) 0.065f else 0.13f
                strokeCap = Paint.Cap.ROUND
            }
            val ratio = amount.toFloat() / max(1, target)
            val edge = paint.strokeWidth / 2 + 2
            val inset = edge + if (segmented && ratio > 1) paint.strokeWidth + size * 0.03f else 0f
            val bounds = RectF(inset, inset, size - inset, size - inset)
            val track = Color.rgb(228, 235, 221)
            paint.color = track
            canvas.drawArc(bounds, 0f, 360f, false, paint)
            if (segmented) {
                paint.strokeCap = Paint.Cap.BUTT
                val starts = floatArrayOf(0f, .3f, .7f)
                val ends = floatArrayOf(.3f, .7f, 1f)
                val colors = intArrayOf(ACCENT, Color.rgb(107, 159, 82), Color.rgb(184, 227, 107))
                starts.indices.forEach { i ->
                    val sweep = (min(ratio, ends[i]) - starts[i]).coerceAtLeast(0f) * 360
                    paint.color = colors[i]
                    canvas.drawArc(bounds, -90 + starts[i] * 360, sweep, false, paint)
                }
                if (ratio > 1) {
                    val outer = RectF(edge, edge, size - edge, size - edge)
                    paint.color = track
                    canvas.drawArc(outer, 0f, 360f, false, paint)
                    paint.color = Color.rgb(241, 185, 99)
                    canvas.drawArc(outer, -90f, (ratio - 1).coerceIn(0f, 1f) * 360, false, paint)
                }
            } else {
                paint.color = color
                canvas.drawArc(bounds, -90f, 360f * ratio.coerceIn(0f, 1f), false, paint)
            }
            return bitmap
        }
    }
}

class CalorieWidget : KayleoWidgetProvider()
class StreakWidget : KayleoWidgetProvider()
class RingsWidget : KayleoWidgetProvider()
class BarcodeWidget : KayleoWidgetProvider()
