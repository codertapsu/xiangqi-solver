package com.xiangqisolver.xiangqi_solver

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * Hosts the visible, draggable floating widget shown while Solver Mode is active.
 *
 * Layout:
 *  - A large, always-visible Analyze button (one tap to analyze; it shows a
 *    spinner + gentle pulse while busy — no text).
 *  - A small secondary "more" FAB that expands Select-area + Stop.
 *  - A result panel placed beside the controls, on whichever side has room.
 *
 * The widget is intentionally obvious and never disguised. Dragging the Analyze
 * button (or the small FAB) repositions the whole cluster.
 */
class OverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var rootRow: LinearLayout? = null
    private var controlsColumn: View? = null
    private var analyzeButton: View? = null
    private var analyzeIcon: View? = null
    private var analyzeProgress: View? = null
    private var settingsFab: ImageButton? = null
    private var menuView: View? = null
    private var switchSideButton: TextView? = null
    private var resultPanel: View? = null
    private var resultTitle: TextView? = null
    private var resultDetail: TextView? = null
    private lateinit var layoutParams: WindowManager.LayoutParams

    private val mainHandler = Handler(Looper.getMainLooper())
    private var regionOverlay: RegionSelectionOverlay? = null

    // Drag bookkeeping.
    private var initialX = 0
    private var initialY = 0
    private var touchStartRawX = 0f
    private var touchStartRawY = 0f
    private var isDragging = false
    private var touchSlop = 0

    /** The Analyze button's left-edge screen X; the cluster is anchored to it. */
    private var anchorLeftX = 0

    /** Whether the result panel currently sits to the LEFT of the controls. */
    private var resultOnLeft = false

    /** The user's current side, mirrored from Dart; drives the toggle's look. */
    private var currentSide = Constants.SIDE_RED

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        touchSlop = ViewConfiguration.get(this).scaledTouchSlop
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            Constants.ACTION_STOP_OVERLAY -> {
                stopSelf()
                return START_NOT_STICKY
            }
            else -> showOverlay()
        }
        return START_STICKY
    }

    private fun showOverlay() {
        if (overlayView != null) return
        if (!Settings.canDrawOverlays(this)) {
            SolverEventBus.emit(
                Constants.EVENT_PERMISSION_DENIED,
                mapOf(Constants.KEY_PERMISSION to Constants.PERMISSION_OVERLAY),
            )
            stopSelf()
            return
        }

        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val view = LayoutInflater.from(this).inflate(R.layout.overlay_widget, null)
        overlayView = view
        rootRow = view.findViewById(R.id.overlay_root)
        controlsColumn = view.findViewById(R.id.overlay_controls)
        analyzeButton = view.findViewById(R.id.overlay_analyze)
        analyzeIcon = view.findViewById(R.id.analyze_icon)
        analyzeProgress = view.findViewById(R.id.analyze_progress)
        settingsFab = view.findViewById(R.id.overlay_menu_fab)
        menuView = view.findViewById(R.id.overlay_menu)
        switchSideButton = view.findViewById(R.id.menu_switch_side)
        resultPanel = view.findViewById(R.id.overlay_result)
        resultTitle = view.findViewById(R.id.result_title)
        resultDetail = view.findViewById(R.id.result_detail)

        layoutParams = buildLayoutParams()
        anchorLeftX = layoutParams.x

        analyzeButton?.let { setupTouch(it) { onAnalyze() } }
        settingsFab?.let { setupTouch(it) { toggleMenu() } }
        wireMenu(view)
        applySide() // reflect the last-known side on the toggle

        runCatching { wm.addView(view, layoutParams) }
            .onFailure { stopSelf() }
    }

    private fun buildLayoutParams(): WindowManager.LayoutParams {
        val type = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = 240
        }
    }

    // --- Touch / drag ---

    private fun setupTouch(view: View, onTap: () -> Unit) {
        view.setOnTouchListener { _, event -> handleTouch(event, onTap) }
    }

    /**
     * Shared drag handler. A press that never crosses the touch slop is a tap
     * ([onTap]); otherwise the whole cluster is dragged, anchored to the Analyze
     * button so the result/menu offsets stay correct.
     */
    private fun handleTouch(event: MotionEvent, onTap: () -> Unit): Boolean {
        val wm = windowManager ?: return false
        val view = overlayView ?: return false
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                initialX = anchorLeftX
                initialY = layoutParams.y
                touchStartRawX = event.rawX
                touchStartRawY = event.rawY
                isDragging = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - touchStartRawX
                val dy = event.rawY - touchStartRawY
                if (!isDragging && (abs(dx) > touchSlop || abs(dy) > touchSlop)) {
                    isDragging = true
                }
                if (isDragging) {
                    anchorLeftX = initialX + dx.toInt()
                    layoutParams.x = windowXForAnchor()
                    layoutParams.y = initialY + dy.toInt()
                    runCatching { wm.updateViewLayout(view, layoutParams) }
                }
                return true
            }
            MotionEvent.ACTION_UP -> {
                if (!isDragging) onTap()
                isDragging = false
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                isDragging = false
                return true
            }
        }
        return false
    }

    /** Window X that keeps the Analyze button at [anchorLeftX] for the current layout. */
    private fun windowXForAnchor(): Int {
        val resultShowing = resultPanel?.visibility == View.VISIBLE
        return if (resultShowing && resultOnLeft) anchorLeftX - resultBlockWidthPx() else anchorLeftX
    }

    // --- Secondary menu (Select area + Stop) ---

    private fun toggleMenu() {
        val menu = menuView ?: return
        setMenuExpanded(menu.visibility != View.VISIBLE)
    }

    private fun setMenuExpanded(expanded: Boolean) {
        menuView?.visibility = if (expanded) View.VISIBLE else View.GONE
        settingsFab?.setImageResource(
            if (expanded) R.drawable.ic_overlay_close else R.drawable.ic_overlay_more,
        )
    }

    private fun wireMenu(root: View) {
        root.findViewById<View>(R.id.menu_select_area).setOnClickListener {
            setMenuExpanded(false)
            onSelectArea()
        }
        root.findViewById<View>(R.id.menu_switch_side).setOnClickListener {
            // Keep the menu open so the user sees the side flip; Dart owns the
            // setting and echoes the new side back via [showSide].
            onSwitchSide()
        }
        root.findViewById<View>(R.id.menu_stop).setOnClickListener {
            setMenuExpanded(false)
            onStop()
        }
    }

    private fun onSwitchSide() {
        SolverEventBus.emit(Constants.EVENT_OVERLAY_ACTION_SWITCH_SIDE)
    }

    /**
     * Update the side toggle to [side] ("red"/"black"). Source of truth is the
     * Dart `mySide` setting; called from the MethodChannel after a toggle or at
     * solver-mode start. Safe to call from any thread.
     */
    fun showSide(side: String) {
        currentSide = if (side == Constants.SIDE_BLACK) Constants.SIDE_BLACK else Constants.SIDE_RED
        mainHandler.post { applySide() }
    }

    private fun applySide() {
        val button = switchSideButton ?: return
        val isRed = currentSide != Constants.SIDE_BLACK
        button.text = if (isRed) "R" else "B"
        button.backgroundTintList = ColorStateList.valueOf(
            if (isRed) 0xFFE53935.toInt() else 0xFF455A64.toInt(),
        )
    }

    // --- Analyze + result panel ---

    private fun onAnalyze() {
        // Collapse transient UI, show the busy animation, and trigger one capture.
        setMenuExpanded(false)
        collapseResult()
        setLoading(true)
        ScreenCaptureService.captureOnce(applicationContext)
        SolverEventBus.emit(Constants.EVENT_OVERLAY_ACTION_ANALYZE)
    }

    private fun setLoading(loading: Boolean) {
        // A clean circular spinner replaces the icon while busy (no pulse).
        analyzeIcon?.visibility = if (loading) View.INVISIBLE else View.VISIBLE
        analyzeProgress?.visibility = if (loading) View.VISIBLE else View.GONE
    }

    /**
     * Update the floating result panel. Safe to call from any thread (e.g. via
     * [OverlayService.instance] from the MethodChannel). A "loading" kind just
     * starts the busy animation; any other kind shows the result text.
     */
    fun showStatus(title: String, detail: String?, kind: String) {
        mainHandler.post {
            if (kind == Constants.OVERLAY_KIND_LOADING) {
                setLoading(true)
                return@post
            }
            setLoading(false)
            showResult(title, detail, kind)
        }
    }

    private fun showResult(title: String, detail: String?, kind: String) {
        val panel = resultPanel ?: return
        val row = rootRow ?: return

        resultTitle?.setTextColor(
            when (kind) {
                Constants.OVERLAY_KIND_ERROR -> 0xFFFF8A80.toInt() // soft red
                else -> 0xFF8BC34A.toInt() // green for a result
            },
        )
        resultTitle?.text = title
        if (detail.isNullOrBlank()) {
            resultDetail?.visibility = View.GONE
        } else {
            resultDetail?.text = detail
            resultDetail?.visibility = View.VISIBLE
        }

        // Place the panel on whichever side of the screen has room.
        val analyzeW = analyzeButton?.width?.takeIf { it > 0 } ?: dp(62)
        resultOnLeft = (anchorLeftX + analyzeW / 2) > screenWidthPx() / 2
        row.removeView(panel)
        if (resultOnLeft) row.addView(panel, 0) else row.addView(panel)
        panel.visibility = View.VISIBLE

        layoutParams.x = windowXForAnchor()
        runCatching { windowManager?.updateViewLayout(overlayView, layoutParams) }
    }

    private fun collapseResult() {
        val panel = resultPanel ?: return
        panel.visibility = View.GONE
        resultOnLeft = false
        // Keep [controls][result] order so the controls stay at the window origin.
        rootRow?.let { row ->
            if (row.indexOfChild(controlsColumn) != 0) {
                row.removeView(panel)
                row.addView(panel)
            }
        }
        layoutParams.x = anchorLeftX
        runCatching { windowManager?.updateViewLayout(overlayView, layoutParams) }
    }

    private fun resultBlockWidthPx(): Int = dp(200 + 10 + 10) // width + start/end margins

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    @Suppress("DEPRECATION")
    private fun screenWidthPx(): Int {
        val wm = windowManager ?: return resources.displayMetrics.widthPixels
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            wm.currentWindowMetrics.bounds.width()
        } else {
            val dm = DisplayMetrics().also { wm.defaultDisplay.getRealMetrics(it) }
            dm.widthPixels
        }
    }

    // --- Actions ---

    private fun onSelectArea() = beginRegionSelection()

    /** Show the resizable focus-area selector. Callable from the MethodChannel. */
    fun beginRegionSelection() {
        val overlay = regionOverlay
            ?: RegionSelectionOverlay(applicationContext).also { regionOverlay = it }
        mainHandler.post { overlay.show() }
    }

    private fun onStop() {
        SolverEventBus.emit(Constants.EVENT_OVERLAY_ACTION_STOP)
        ScreenCaptureService.stop(applicationContext)
        MediaProjectionHolder.clear()
        SolverController.setRunning(false)
        SolverEventBus.emit(Constants.EVENT_SOLVER_MODE_STOPPED)
        stopSelf()
    }

    // --- Teardown ---

    private fun removeOverlay() {
        val wm = windowManager
        val view = overlayView
        if (wm != null && view != null) {
            runCatching { wm.removeView(view) }
        }
        overlayView = null
        rootRow = null
        controlsColumn = null
        analyzeButton = null
        analyzeIcon = null
        analyzeProgress = null
        settingsFab = null
        menuView = null
        switchSideButton = null
        resultPanel = null
        resultTitle = null
        resultDetail = null
        windowManager = null
    }

    override fun onDestroy() {
        regionOverlay?.dismiss()
        regionOverlay = null
        if (instance === this) instance = null
        removeOverlay()
        super.onDestroy()
    }

    companion object {
        /** Live instance so the Activity/MethodChannel can update the panel. */
        @Volatile
        var instance: OverlayService? = null
            private set

        fun start(context: Context) {
            val intent = Intent(context, OverlayService::class.java).apply {
                action = Constants.ACTION_START_OVERLAY
            }
            // A plain started service is sufficient; the overlay window itself
            // requires SYSTEM_ALERT_WINDOW, not a foreground service type.
            context.startService(intent)
        }

        fun stop(context: Context) {
            runCatching {
                context.stopService(Intent(context, OverlayService::class.java))
            }
        }
    }
}
