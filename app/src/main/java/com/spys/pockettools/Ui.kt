package com.spys.pockettools

import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.View
import android.widget.TextView

/** App palette: one dark ground, one mint accent. */
object C {
    const val BG = 0xFF0F1115.toInt()
    const val SURFACE = 0xFF181B22.toInt()
    const val SURFACE2 = 0xFF242833.toInt()
    const val LINE = 0xFF2E3340.toInt()
    const val TEXT = 0xFFEDEFF3.toInt()
    const val MUTED = 0xFF8A90A0.toInt()
    const val ACCENT = 0xFF5EEAD4.toInt()
    const val ON_ACCENT = 0xFF06201C.toInt()
    const val WARN = 0xFFFBBF24.toInt()
    const val DANGER = 0xFFF87171.toInt()
}

fun Context.dp(v: Float): Float = v * resources.displayMetrics.density
fun Context.dpi(v: Int): Int = (v * resources.displayMetrics.density).toInt()

val MEDIUM: Typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)

fun roundBg(color: Int, radius: Float, strokeColor: Int = 0, strokeWidth: Int = 0): GradientDrawable =
    GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius
        if (strokeWidth > 0) setStroke(strokeWidth, strokeColor)
    }

fun Context.vibrate(ms: Long) {
    val v = getSystemService(Vibrator::class.java) ?: return
    if (!v.hasVibrator()) return
    v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
}

fun Context.label(text: String, sizeSp: Float, color: Int = C.TEXT, medium: Boolean = false): TextView =
    TextView(this).apply {
        this.text = text
        textSize = sizeSp
        setTextColor(color)
        if (medium) typeface = MEDIUM
    }

/** A filled pill button. */
fun Context.pillButton(text: String, primary: Boolean, onClick: (View) -> Unit): TextView =
    TextView(this).apply {
        this.text = text
        textSize = 16f
        typeface = MEDIUM
        gravity = Gravity.CENTER
        setPadding(dpi(20), dpi(14), dpi(20), dpi(14))
        setTextColor(if (primary) C.ON_ACCENT else C.TEXT)
        background = roundBg(if (primary) C.ACCENT else C.SURFACE2, dp(28f))
        isClickable = true
        setOnClickListener(onClick)
    }
