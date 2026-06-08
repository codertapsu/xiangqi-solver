package com.codertapsu.xiangqi_solver

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and wires the platform channels to the native solver.
 *
 * Responsibilities:
 *  - Implement every method of the Dart <-> native contract.
 *  - Bridge the EventChannel to the process-wide [SolverEventBus].
 *  - Drive the OFFICIAL MediaProjection consent flow and resolve the pending
 *    Flutter result asynchronously.
 *
 * It deliberately holds no long-lived references to native services; services
 * reach Flutter through [SolverEventBus] instead, avoiding Activity leaks.
 */
class MainActivity : FlutterActivity() {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        methodChannel = MethodChannel(messenger, Constants.METHOD_CHANNEL).also {
            it.setMethodCallHandler(::onMethodCall)
        }

        eventChannel = EventChannel(messenger, Constants.EVENT_CHANNEL).also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    SolverEventBus.attach(events)
                }

                override fun onCancel(arguments: Any?) {
                    SolverEventBus.detach()
                }
            })
        }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            Constants.METHOD_CHECK_OVERLAY_PERMISSION ->
                result.success(Settings.canDrawOverlays(this))

            Constants.METHOD_REQUEST_OVERLAY_PERMISSION ->
                requestOverlayPermission(result)

            Constants.METHOD_REQUEST_SCREEN_CAPTURE_PERMISSION ->
                requestScreenCapturePermission(result)

            Constants.METHOD_START_SOLVER_MODE ->
                startSolverMode(result)

            Constants.METHOD_STOP_SOLVER_MODE ->
                stopSolverMode(result)

            Constants.METHOD_IS_SOLVER_MODE_RUNNING ->
                result.success(SolverController.isRunning)

            Constants.METHOD_CAPTURE_SCREENSHOT ->
                captureScreenshot(result)

            Constants.METHOD_UPDATE_OVERLAY ->
                updateOverlay(call, result)

            Constants.METHOD_START_REGION_SELECTION ->
                startRegionSelection(result)

            Constants.METHOD_CLEAR_CAPTURE_REGION -> {
                CaptureRegionHolder.clear()
                result.success(null)
            }

            Constants.METHOD_HAS_CAPTURE_REGION ->
                result.success(CaptureRegionHolder.hasRegion)

            Constants.METHOD_NATIVE_LIBRARY_DIR ->
                result.success(applicationInfo.nativeLibraryDir)

            Constants.METHOD_SET_OVERLAY_SIDE -> {
                OverlayService.instance?.showSide(
                    call.argument<String>(Constants.KEY_SIDE) ?: Constants.SIDE_RED,
                )
                result.success(null)
            }

            Constants.METHOD_SET_APP_ICON -> {
                setAppIcon(call.argument<String>(Constants.KEY_VARIANT))
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // --- Overlay permission ---

    /**
     * Opens the system overlay-settings screen. The contract returns void, so we
     * resolve immediately after launching; the actual grant is observed later
     * via checkOverlayPermission().
     */
    private fun requestOverlayPermission(result: MethodChannel.Result) {
        if (Settings.canDrawOverlays(this)) {
            result.success(null)
            return
        }
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName"),
        ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        runCatching { startActivity(intent) }
            .onFailure {
                result.error(
                    "OVERLAY_SETTINGS_UNAVAILABLE",
                    "Could not open overlay settings",
                    it.message,
                )
                return
            }
        result.success(null)
    }

    // --- Screen-capture (MediaProjection) consent ---

    /**
     * Launches the OFFICIAL MediaProjection consent dialog through the
     * transparent [MediaProjectionPermissionActivity] and resolves the Flutter
     * result with true iff the user granted capture.
     */
    private fun requestScreenCapturePermission(result: MethodChannel.Result) {
        MediaProjectionPermissionActivity.ResultBridge.setCallback { granted ->
            mainHandler.post {
                if (!granted) {
                    SolverEventBus.emit(
                        Constants.EVENT_PERMISSION_DENIED,
                        mapOf(Constants.KEY_PERMISSION to Constants.PERMISSION_PROJECTION),
                    )
                }
                result.success(granted)
            }
        }
        val intent = Intent(this, MediaProjectionPermissionActivity::class.java)
            .apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        runCatching { startActivity(intent) }
            .onFailure {
                MediaProjectionPermissionActivity.ResultBridge.deliver(false)
            }
    }

    // --- Solver Mode lifecycle ---

    /**
     * Starts Solver Mode only when BOTH overlay and projection are granted. If
     * either is missing we emit the matching permissionDenied event and refuse.
     */
    private fun startSolverMode(result: MethodChannel.Result) {
        if (!Settings.canDrawOverlays(this)) {
            SolverEventBus.emit(
                Constants.EVENT_PERMISSION_DENIED,
                mapOf(Constants.KEY_PERMISSION to Constants.PERMISSION_OVERLAY),
            )
            result.error(
                Constants.PERMISSION_OVERLAY,
                "Overlay permission not granted",
                null,
            )
            return
        }
        if (!MediaProjectionHolder.hasConsent) {
            SolverEventBus.emit(
                Constants.EVENT_PERMISSION_DENIED,
                mapOf(Constants.KEY_PERMISSION to Constants.PERMISSION_PROJECTION),
            )
            result.error(
                Constants.PERMISSION_PROJECTION,
                "Screen capture permission not granted",
                null,
            )
            return
        }

        ScreenCaptureService.start(this)
        OverlayService.start(this)
        SolverController.setRunning(true)
        SolverEventBus.emit(Constants.EVENT_SOLVER_MODE_STARTED)
        result.success(null)
    }

    private fun stopSolverMode(result: MethodChannel.Result) {
        OverlayService.stop(this)
        ScreenCaptureService.stop(this)
        MediaProjectionHolder.clear()
        SolverController.setRunning(false)
        SolverEventBus.emit(Constants.EVENT_SOLVER_MODE_STOPPED)
        result.success(null)
    }

    // --- Screenshot ---

    /**
     * Asks the live [ScreenCaptureService] for a single frame. Resolves with the
     * saved file path, or throws a PlatformException carrying a precise code.
     * The capture itself runs off the main thread inside the service.
     */
    private fun captureScreenshot(result: MethodChannel.Result) {
        if (!SolverController.isRunning) {
            result.error(
                Constants.ERROR_NOT_RUNNING,
                "Solver Mode is not running",
                null,
            )
            return
        }
        val service = ScreenCaptureService.instance
        if (service == null) {
            result.error(
                Constants.ERROR_NO_SERVICE,
                "Capture service is not available",
                null,
            )
            return
        }

        // Run the blocking capture off the UI thread, then resolve on main.
        Thread {
            val outcome = service.captureBlocking()
            mainHandler.post {
                when (outcome) {
                    is ScreenCaptureService.CaptureResult.Success ->
                        result.success(outcome.path)

                    is ScreenCaptureService.CaptureResult.Failure ->
                        result.error(outcome.code, outcome.reason, null)
                }
            }
        }.apply { name = "xiangqi-capture-bridge" }.start()
    }

    // --- Overlay result panel + focus-area selection ---

    /** Push a status/result line into the floating overlay panel. */
    private fun updateOverlay(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>(Constants.KEY_TITLE) ?: ""
        val detail = call.argument<String>(Constants.KEY_DETAIL)
        val kind = call.argument<String>(Constants.KEY_KIND) ?: Constants.OVERLAY_KIND_RESULT
        OverlayService.instance?.showStatus(title, detail, kind)
        result.success(null)
    }

    /** Open the resizable focus-area selector over the screen. */
    private fun startRegionSelection(result: MethodChannel.Result) {
        if (!Settings.canDrawOverlays(this)) {
            SolverEventBus.emit(
                Constants.EVENT_PERMISSION_DENIED,
                mapOf(Constants.KEY_PERMISSION to Constants.PERMISSION_OVERLAY),
            )
            result.error(Constants.PERMISSION_OVERLAY, "Overlay permission not granted", null)
            return
        }
        val overlay = OverlayService.instance
        if (overlay == null) {
            result.error(Constants.ERROR_NOT_RUNNING, "Solver Mode is not running", null)
            return
        }
        overlay.beginRegionSelection()
        result.success(null)
    }

    // --- Dynamic launcher icon + name (activity-alias) ---

    /**
     * Switches the launcher icon + name to the [variant] ('vi' | 'en') by
     * enabling the matching activity-alias and disabling the other. Idempotent:
     * if the target is already the active launcher it does nothing, so a launch
     * with the variant already correct never causes the brief icon flash some
     * launchers show on a component-state change. [PackageManager.DONT_KILL_APP]
     * keeps the running app alive across the switch.
     */
    private fun setAppIcon(variant: String?) {
        val target = when (variant) {
            Constants.VARIANT_VI -> Constants.ALIAS_LAUNCHER_VI
            Constants.VARIANT_EN -> Constants.ALIAS_LAUNCHER_EN
            else -> return // unknown variant → leave the current launcher as-is
        }
        val pm = packageManager
        if (isAliasActive(pm, target)) return
        for (alias in listOf(Constants.ALIAS_LAUNCHER_VI, Constants.ALIAS_LAUNCHER_EN)) {
            val state = if (alias == target) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            pm.setComponentEnabledSetting(
                aliasComponent(alias),
                state,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    /**
     * Whether [alias] is the currently-active launcher. A never-toggled
     * component reports STATE_DEFAULT, which means "use the manifest value" — so
     * the VI alias (android:enabled="true") is active when DEFAULT, the EN alias
     * (android:enabled="false") is not.
     */
    private fun isAliasActive(pm: PackageManager, alias: String): Boolean {
        return when (pm.getComponentEnabledSetting(aliasComponent(alias))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> alias == Constants.ALIAS_LAUNCHER_VI
            else -> false
        }
    }

    /**
     * Resolves an activity-alias [ComponentName]. The alias CLASS names live under
     * the manifest namespace (com.codertapsu.xiangqi_solver), which can differ
     * from the applicationId/`packageName` when a build sets an
     * applicationIdSuffix (e.g. `.dev`). We derive the namespace from this
     * activity's own class so the lookup is correct in every build variant;
     * `ComponentName(this, ...)` still uses the runtime applicationId as the
     * package, which is what `setComponentEnabledSetting` expects.
     */
    private fun aliasComponent(alias: String): ComponentName {
        val namespace = javaClass.name.substringBeforeLast('.')
        return ComponentName(this, "$namespace.$alias")
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        SolverEventBus.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
