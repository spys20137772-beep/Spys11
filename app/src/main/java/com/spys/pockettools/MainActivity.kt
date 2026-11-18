package com.spys.pockettools

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/** One tool = one page in the bottom tab bar. */
abstract class ToolPage(val act: MainActivity) {
    abstract val title: String
    abstract val subtitle: String
    abstract val icon: String
    abstract val tabLabel: String
    abstract val view: View
    open fun onShow() {}
    open fun onHide() {}
    open fun onPermissionResult(requestCode: Int, granted: Boolean) {}
}

class MainActivity : Activity() {
    private lateinit var container: FrameLayout
    private lateinit var titleView: TextView
    private lateinit var subView: TextView
    private lateinit var pages: List<ToolPage>
    private val tabs = mutableListOf<LinearLayout>()
    private var current = -1
    private var isResumedNow = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(C.BG)
            fitsSystemWindows = true
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dpi(24), dpi(20), dpi(24), dpi(4))
        }
        titleView = label("", 28f, C.TEXT, medium = true)
        subView = label("", 14f, C.MUTED).apply { setPadding(0, dpi(4), 0, 0) }
        header.addView(titleView)
        header.addView(subView)

        container = FrameLayout(this)

        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(C.SURFACE)
            setPadding(dpi(8), dpi(8), dpi(8), dpi(8))
        }

        pages = listOf(
            LevelPage(this),
            CompassPage(this),
            SoundPage(this),
            FlashPage(this),
            DecidePage(this),
        )

        pages.forEachIndexed { i, p ->
            val tab = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(0, dpi(6), 0, dpi(6))
                isClickable = true
                setOnClickListener { select(i) }
            }
            tab.addView(label(p.icon, 20f).apply { gravity = Gravity.CENTER })
            tab.addView(label(p.tabLabel, 11f, C.MUTED).apply {
                gravity = Gravity.CENTER
                setPadding(0, dpi(2), 0, 0)
            })
            bar.addView(tab, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
            tabs += tab
        }

        root.addView(header, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        root.addView(container, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
        root.addView(bar, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setContentView(root)

        select(savedInstanceState?.getInt("tab") ?: 0)
    }

    private fun select(i: Int) {
        if (i == current) return
        if (current >= 0 && isResumedNow) pages[current].onHide()
        current = i
        container.removeAllViews()
        val v = pages[i].view
        (v.parent as? android.view.ViewGroup)?.removeView(v)
        container.addView(v, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        titleView.text = pages[i].title
        subView.text = pages[i].subtitle
        tabs.forEachIndexed { j, t ->
            val sel = j == i
            t.background = if (sel) roundBg(C.SURFACE2, dp(14f)) else null
            (t.getChildAt(1) as TextView).setTextColor(if (sel) C.ACCENT else C.MUTED)
            t.getChildAt(0).alpha = if (sel) 1f else 0.5f
        }
        if (isResumedNow) pages[i].onShow()
    }

    override fun onResume() {
        super.onResume()
        isResumedNow = true
        pages[current].onShow()
    }

    override fun onPause() {
        isResumedNow = false
        pages[current].onHide()
        super.onPause()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt("tab", current)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pages.forEach { it.onPermissionResult(requestCode, granted) }
    }
}
