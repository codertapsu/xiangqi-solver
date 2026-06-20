package com.codertapsu.xiangqi_solver

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.os.Build
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import kotlin.math.abs

/**
 * A full-screen, dismissable overlay that lets the user draw a resizable focus
 * box over the screen. The chosen rectangle is stored (normalized) in
 * [CaptureRegionHolder] so subsequent captures are cropped to just that area
 * (e.g. only the chessboard).
 *
 * Everything is built programmatically to avoid an extra layout resource. The
 * box is initialised from any previously-saved region so re-opening tweaks the
 * existing selection instead of starting over.
 */
class RegionSelectionOverlay(private val context: Context) {

    private var windowManager: WindowManager? = null
    private var rootView: View? = null

    fun isShowing(): Boolean = rootView != null

    @SuppressLint("ClickableViewAccessibility")
    fun show() {
        if (rootView != null) return
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val selector = SelectorView(context)

        val controls = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(24, 16, 24, 16)
            setBackgroundColor(0xCC000000.toInt())
        }
        controls.addView(makeButton("Full screen") {
            CaptureRegionHolder.clear()
            dismiss()
        })
        controls.addView(makeButton("Cancel") { dismiss() })
        controls.addView(makeButton("Use this area") {
            val r = selector.normalizedRegion()
            CaptureRegionHolder.set(r.left, r.top, r.right, r.bottom)
            dismiss()
        })

        val container = FrameLayout(context)
        container.addView(
            selector,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        container.addView(
            controls,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ),
        )
        rootView = container

        // The selection MUST live in the exact same coordinate space as the
        // captured bitmap, which ScreenCaptureService sizes to the FULL physical
        // display (currentWindowMetrics.bounds, incl. status/nav bars, origin at
        // the true top-left). MATCH_PARENT alone does NOT guarantee that: without
        // FLAG_LAYOUT_IN_SCREEN the window frame is inset by the system bars, so
        // the SelectorView would measure smaller and offset, and normalizedRegion
        // (fractions of the view) would then map onto the larger bitmap shifted +
        // stretched — the reported crop mismatch. Sizing the window explicitly to
        // the same bounds and adding IN_SCREEN pins selection-space == capture-space.
        val (dispW, dispH) = displaySize(wm)
        val params = WindowManager.LayoutParams(
            dispW,
            dispH,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 0
            // Extend under a display cutout/notch too — the capture includes that
            // band, so the selection space must as well.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            }
        }

        // The SelectorView is now truly full-display; keep the bottom controls
        // clear of the navigation bar by padding them with the bottom system-bar
        // inset, without shrinking the (full-display) selection space.
        container.setOnApplyWindowInsetsListener { _, insets ->
            controls.setPadding(24, 16, 24, 16 + systemBarBottomInset(insets))
            insets
        }

        runCatching { wm.addView(container, params) }.onFailure { dismiss() }
    }

    fun dismiss() {
        val wm = windowManager
        val view = rootView
        if (wm != null && view != null) {
            runCatching { wm.removeView(view) }
        }
        rootView = null
        windowManager = null
    }

    /**
     * Full physical display size in the current rotation, INCLUDING the system
     * bars — the exact extent [ScreenCaptureService] mirrors into the capture
     * bitmap, so the selection and the capture share one coordinate space.
     */
    @Suppress("DEPRECATION")
    private fun displaySize(wm: WindowManager): Pair<Int, Int> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = wm.currentWindowMetrics.bounds
            b.width() to b.height()
        } else {
            val m = DisplayMetrics().also { wm.defaultDisplay.getRealMetrics(it) }
            m.widthPixels to m.heightPixels
        }
    }

    /** Bottom system-bar (navigation bar) inset, across API levels. */
    @Suppress("DEPRECATION")
    private fun systemBarBottomInset(insets: WindowInsets): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            insets.getInsets(WindowInsets.Type.systemBars()).bottom
        } else {
            insets.systemWindowInsetBottom
        }
    }

    private fun makeButton(label: String, onClick: () -> Unit): Button {
        return Button(context).apply {
            text = label
            isAllCaps = false
            setOnClickListener { onClick() }
            val lp = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            lp.marginStart = 8
            lp.marginEnd = 8
            layoutParams = lp
        }
    }

    /** Custom view that draws the dimmed scrim, the selection box, and handles. */
    private class SelectorView(context: Context) : View(context) {

        private val sel = RectF()
        private var initialised = false

        private val scrimPaint = Paint().apply { color = 0x99000000.toInt() }
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            color = Color.WHITE
            strokeWidth = 6f
        }
        private val handlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = 0xFF4CAF50.toInt()
        }
        private val hintPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 36f
            textAlign = Paint.Align.CENTER
        }

        private val handleRadius = 36f
        private val minSize = 120f

        private enum class Mode { NONE, MOVE, TL, TR, BL, BR }
        private var mode = Mode.NONE
        private var lastX = 0f
        private var lastY = 0f

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            if (initialised) return
            val saved = CaptureRegionHolder.region
            if (saved != null) {
                sel.set(saved.left * w, saved.top * h, saved.right * w, saved.bottom * h)
            } else {
                // Default: centered box covering most of the screen.
                val mw = w * 0.08f
                val mh = h * 0.22f
                sel.set(mw, mh, w - mw, h - mh)
            }
            initialised = true
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            // Dim everything outside the selection.
            canvas.drawRect(0f, 0f, w, sel.top, scrimPaint)
            canvas.drawRect(0f, sel.bottom, w, h, scrimPaint)
            canvas.drawRect(0f, sel.top, sel.left, sel.bottom, scrimPaint)
            canvas.drawRect(sel.right, sel.top, w, sel.bottom, scrimPaint)
            // Selection border + corner handles.
            canvas.drawRect(sel, borderPaint)
            for (p in corners()) canvas.drawCircle(p.first, p.second, handleRadius * 0.7f, handlePaint)
            canvas.drawText("Drag to move • drag a corner to resize", w / 2f, sel.top - 24f, hintPaint)
        }

        private fun corners(): List<Pair<Float, Float>> = listOf(
            sel.left to sel.top,
            sel.right to sel.top,
            sel.left to sel.bottom,
            sel.right to sel.bottom,
        )

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    lastX = event.x
                    lastY = event.y
                    mode = hitTest(event.x, event.y)
                    return mode != Mode.NONE
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.x - lastX
                    val dy = event.y - lastY
                    applyDrag(dx, dy)
                    lastX = event.x
                    lastY = event.y
                    invalidate()
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    mode = Mode.NONE
                    return true
                }
            }
            return false
        }

        private fun hitTest(x: Float, y: Float): Mode {
            if (near(x, y, sel.left, sel.top)) return Mode.TL
            if (near(x, y, sel.right, sel.top)) return Mode.TR
            if (near(x, y, sel.left, sel.bottom)) return Mode.BL
            if (near(x, y, sel.right, sel.bottom)) return Mode.BR
            if (sel.contains(x, y)) return Mode.MOVE
            return Mode.NONE
        }

        private fun near(x: Float, y: Float, cx: Float, cy: Float): Boolean =
            abs(x - cx) <= handleRadius && abs(y - cy) <= handleRadius

        private fun applyDrag(dx: Float, dy: Float) {
            val w = width.toFloat()
            val h = height.toFloat()
            when (mode) {
                Mode.MOVE -> {
                    var nl = sel.left + dx
                    var nt = sel.top + dy
                    nl = nl.coerceIn(0f, w - sel.width())
                    nt = nt.coerceIn(0f, h - sel.height())
                    sel.offsetTo(nl, nt)
                }
                Mode.TL -> {
                    sel.left = (sel.left + dx).coerceIn(0f, sel.right - minSize)
                    sel.top = (sel.top + dy).coerceIn(0f, sel.bottom - minSize)
                }
                Mode.TR -> {
                    sel.right = (sel.right + dx).coerceIn(sel.left + minSize, w)
                    sel.top = (sel.top + dy).coerceIn(0f, sel.bottom - minSize)
                }
                Mode.BL -> {
                    sel.left = (sel.left + dx).coerceIn(0f, sel.right - minSize)
                    sel.bottom = (sel.bottom + dy).coerceIn(sel.top + minSize, h)
                }
                Mode.BR -> {
                    sel.right = (sel.right + dx).coerceIn(sel.left + minSize, w)
                    sel.bottom = (sel.bottom + dy).coerceIn(sel.top + minSize, h)
                }
                Mode.NONE -> {}
            }
        }

        fun normalizedRegion(): RectF {
            val w = width.toFloat().coerceAtLeast(1f)
            val h = height.toFloat().coerceAtLeast(1f)
            return RectF(sel.left / w, sel.top / h, sel.right / w, sel.bottom / h)
        }
    }
}
