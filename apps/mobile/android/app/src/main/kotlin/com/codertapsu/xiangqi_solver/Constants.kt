package com.codertapsu.xiangqi_solver

/**
 * Central place for every string/id shared between the Flutter platform channels
 * and the native services. Keeping them here avoids magic strings and guarantees
 * the Dart <-> native contract stays in one obvious location (DRY).
 */
object Constants {

    // --- Platform channels (MUST match the Dart side exactly). ---
    const val METHOD_CHANNEL = "com.xiangqisolver/solver/methods"
    const val EVENT_CHANNEL = "com.xiangqisolver/solver/events"

    // --- MethodChannel method names. ---
    const val METHOD_CHECK_OVERLAY_PERMISSION = "checkOverlayPermission"
    const val METHOD_REQUEST_OVERLAY_PERMISSION = "requestOverlayPermission"
    const val METHOD_REQUEST_SCREEN_CAPTURE_PERMISSION = "requestScreenCapturePermission"
    const val METHOD_START_SOLVER_MODE = "startSolverMode"
    const val METHOD_STOP_SOLVER_MODE = "stopSolverMode"
    const val METHOD_IS_SOLVER_MODE_RUNNING = "isSolverModeRunning"
    const val METHOD_CAPTURE_SCREENSHOT = "captureScreenshot"

    // Overlay result panel + capture-region selection.
    const val METHOD_UPDATE_OVERLAY = "updateOverlay"
    const val METHOD_START_REGION_SELECTION = "startRegionSelection"
    const val METHOD_CLEAR_CAPTURE_REGION = "clearCaptureRegion"
    const val METHOD_HAS_CAPTURE_REGION = "hasCaptureRegion"

    // On-device engine: where the bundled lib*.so executables are extracted.
    const val METHOD_NATIVE_LIBRARY_DIR = "nativeLibraryDir"

    // Push the user's current side (red/black) into the overlay's side toggle.
    const val METHOD_SET_OVERLAY_SIDE = "setOverlaySide"

    // Switch the launcher icon + name variant ('vi' | 'en') via activity-alias.
    const val METHOD_SET_APP_ICON = "setAppIcon"
    const val KEY_VARIANT = "variant"
    const val VARIANT_VI = "vi"
    const val VARIANT_EN = "en"

    // Activity-alias simple names (launcher entries; exactly one is enabled at a
    // time). VI is the manifest default (android:enabled="true").
    const val ALIAS_LAUNCHER_VI = "LauncherVi"
    const val ALIAS_LAUNCHER_EN = "LauncherEn"

    // --- Event "type" values emitted on the EventChannel. ---
    const val EVENT_SOLVER_MODE_STARTED = "solverModeStarted"
    const val EVENT_SOLVER_MODE_STOPPED = "solverModeStopped"
    const val EVENT_SCREENSHOT_CAPTURED = "screenshotCaptured"
    const val EVENT_SCREENSHOT_FAILED = "screenshotFailed"
    const val EVENT_PERMISSION_DENIED = "permissionDenied"
    const val EVENT_OVERLAY_ACTION_ANALYZE = "overlayActionAnalyze"
    const val EVENT_OVERLAY_ACTION_STOP = "overlayActionStop"
    const val EVENT_OVERLAY_ACTION_SWITCH_SIDE = "overlayActionSwitchSide"

    // --- Event payload keys. ---
    const val KEY_TYPE = "type"
    const val KEY_PATH = "path"
    const val KEY_WIDTH = "width"
    const val KEY_HEIGHT = "height"
    const val KEY_REASON = "reason"
    const val KEY_CODE = "code"
    const val KEY_PERMISSION = "permission"
    const val KEY_TITLE = "title"
    const val KEY_DETAIL = "detail"
    const val KEY_KIND = "kind"
    const val KEY_SIDE = "side"

    // --- Side identifiers shared with Dart (SideToMove.wireValue). ---
    const val SIDE_RED = "red"
    const val SIDE_BLACK = "black"

    // --- Overlay result panel "kind" values (passed from Dart). ---
    const val OVERLAY_KIND_LOADING = "loading"
    const val OVERLAY_KIND_RESULT = "result"
    const val OVERLAY_KIND_ERROR = "error"

    // --- Permission identifiers used in permissionDenied events. ---
    const val PERMISSION_OVERLAY = "overlay"
    const val PERMISSION_PROJECTION = "projection"

    // --- PlatformException error codes thrown from captureScreenshot. ---
    const val ERROR_NOT_RUNNING = "NOT_RUNNING"
    const val ERROR_NO_SERVICE = "NO_SERVICE"
    const val ERROR_CAPTURE_FAILED = "CAPTURE_FAILED"
    const val ERROR_FLAG_SECURE = "FLAG_SECURE"
    const val ERROR_TIMEOUT = "TIMEOUT"

    // --- Service intent actions. ---
    const val ACTION_START_CAPTURE = "com.xiangqisolver.action.START_CAPTURE"
    const val ACTION_STOP_CAPTURE = "com.xiangqisolver.action.STOP_CAPTURE"
    const val ACTION_CAPTURE_ONCE = "com.xiangqisolver.action.CAPTURE_ONCE"
    const val ACTION_START_OVERLAY = "com.xiangqisolver.action.START_OVERLAY"
    const val ACTION_STOP_OVERLAY = "com.xiangqisolver.action.STOP_OVERLAY"

    // --- Notification. ---
    const val NOTIFICATION_CHANNEL_ID = "xiangqi_solver_capture"
    const val NOTIFICATION_ID = 4711

    // --- Activity request codes. ---
    const val REQUEST_MEDIA_PROJECTION = 9001

    // --- Cache layout for captured frames. Files use a unique name per capture
    // (prefix + timestamp) so an in-flight upload is never overwritten mid-read;
    // older frames are pruned so they never accumulate. ---
    const val CAPTURE_DIR_NAME = "xiangqi"
    const val CAPTURE_FILE_PREFIX = "capture_"
    const val CAPTURE_FILE_EXT = ".png"
    /** Keep at most this many recent capture files on disk. */
    const val CAPTURE_KEEP_FILES = 3

    /** Reason text reused for FLAG_SECURE / black-frame failures. */
    const val REASON_FLAG_SECURE =
        "Target app may block screenshots (FLAG_SECURE)"

    /** Reason text reused when the capture pipeline has not initialised. */
    const val REASON_NOT_READY = "Capture pipeline not ready"
}
