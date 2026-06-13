package com.codertapsu.xiangqi_solver

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream

/**
 * Foreground service (type = mediaProjection) that owns the screen-capture
 * pipeline. It builds a [MediaProjection] from the user-granted consent stored
 * in [MediaProjectionHolder], renders the display into an [ImageReader], and on
 * request grabs exactly one frame, saves it as a downscaled JPEG, and reports the result.
 *
 * Honesty & safety:
 *  - A persistent, clearly worded notification is shown the whole time.
 *  - We only ever read frames the OS hands us through the official projection.
 *    If a frame comes back all-black (FLAG_SECURE windows), we report that
 *    instead of trying to work around the restriction.
 *  - All native resources are released on stop/destroy to avoid leaks.
 */
class ScreenCaptureService : Service() {

    /** Lets the Activity call [captureOnce] directly via a bound connection. */
    inner class LocalBinder : android.os.Binder() {
        val service: ScreenCaptureService get() = this@ScreenCaptureService
    }

    private val binder = LocalBinder()

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null

    private var width = 0
    private var height = 0
    private var density = 0

    @Volatile
    private var started = false

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            // The system or user revoked the projection. Tear down cleanly.
            stopSelfSafely()
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            Constants.ACTION_STOP_CAPTURE -> {
                stopSelfSafely()
                return START_NOT_STICKY
            }
            Constants.ACTION_CAPTURE_ONCE -> {
                ensureStarted()
                captureOnce()
                return START_STICKY
            }
            else -> ensureStarted()
        }
        return START_STICKY
    }

    /**
     * Promote to foreground and build the capture pipeline if not already done.
     * Must run before touching MediaProjection on Android 14+, which requires
     * startForeground(mediaProjection) before MediaProjection use.
     */
    private fun ensureStarted() {
        if (started) return
        instance = this
        startForegroundCompat()

        if (!MediaProjectionHolder.hasConsent) {
            // No granted consent: do not attempt projection. Stay alive only as
            // a foreground placeholder is pointless, so stop and report nothing
            // (MainActivity guards against this path before starting us).
            stopSelfSafely()
            return
        }

        val projection = buildProjection()
        if (projection == null) {
            stopSelfSafely()
            return
        }
        mediaProjection = projection

        startCaptureThread()
        computeDisplayMetrics()
        // Order matters on Android 14+: register the callback BEFORE creating
        // the VirtualDisplay.
        projection.registerCallback(projectionCallback, captureHandler)
        setUpImageReaderAndDisplay(projection)

        started = true
    }

    private fun buildProjection(): MediaProjection? {
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
            ?: return null
        val data = MediaProjectionHolder.resultData ?: return null
        return runCatching {
            manager.getMediaProjection(MediaProjectionHolder.resultCode, data)
        }.getOrNull()
    }

    private fun startCaptureThread() {
        val thread = HandlerThread("xiangqi-capture").apply { start() }
        captureThread = thread
        captureHandler = Handler(thread.looper)
    }

    @Suppress("DEPRECATION")
    private fun computeDisplayMetrics() {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            width = bounds.width()
            height = bounds.height()
            density = resources.displayMetrics.densityDpi
        } else {
            val metrics = DisplayMetrics()
            windowManager.defaultDisplay.getRealMetrics(metrics)
            width = metrics.widthPixels
            height = metrics.heightPixels
            density = metrics.densityDpi
        }
        // Guard against pathological zero sizes.
        if (width <= 0) width = 1080
        if (height <= 0) height = 1920
        if (density <= 0) density = DisplayMetrics.DENSITY_DEFAULT
    }

    private fun setUpImageReaderAndDisplay(projection: MediaProjection) {
        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        imageReader = reader
        virtualDisplay = projection.createVirtualDisplay(
            "xiangqi-capture",
            width,
            height,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface,
            null,
            captureHandler,
        )
    }

    /**
     * Grab one frame and report it through [SolverEventBus]. Runs the actual
     * pixel work on the capture thread so we never block the main thread.
     */
    fun captureOnce() {
        val handler = captureHandler
        if (!started || handler == null) {
            SolverEventBus.emit(
                Constants.EVENT_SCREENSHOT_FAILED,
                mapOf(
                    Constants.KEY_REASON to "Capture pipeline not ready",
                    Constants.KEY_CODE to Constants.ERROR_NO_SERVICE,
                ),
            )
            return
        }
        // Event path: a screenshotCaptured/screenshotFailed event is emitted so
        // Dart can upload. This is the SINGLE source of an upload for an overlay
        // "Analyze" tap.
        handler.post { captureFrameInternal(emit = true) }
    }

    /**
     * Synchronous capture used by the MethodChannel path. Returns the saved file
     * path, or null on failure (the caller turns null into a PlatformException).
     * Emits the matching event in both cases.
     */
    fun captureBlocking(timeoutMs: Long = 2_000L): CaptureResult {
        if (!started) {
            return CaptureResult.Failure(
                Constants.REASON_NOT_READY,
                Constants.ERROR_NO_SERVICE,
            )
        }
        val handler = captureHandler
            ?: return CaptureResult.Failure(
                Constants.REASON_NOT_READY,
                Constants.ERROR_NO_SERVICE,
            )
        val lock = Object()
        var result: CaptureResult? = null
        handler.post {
            // Request path: do NOT emit an event — the caller gets the result
            // back through the return value and turns it into the Dart Future,
            // which avoids a second (duplicate) upload.
            val r = captureFrameInternal(emit = false)
            synchronized(lock) {
                result = r
                lock.notifyAll()
            }
        }
        synchronized(lock) {
            if (result == null) {
                runCatching { lock.wait(timeoutMs) }
            }
        }
        return result ?: CaptureResult.Failure(
            "Capture timed out",
            Constants.ERROR_TIMEOUT,
        )
    }

    /**
     * Core capture: acquire the latest image, copy into a bitmap, detect a black
     * frame, persist a downscaled JPEG, and emit the matching event. Always returns a result.
     */
    private fun captureFrameInternal(emit: Boolean): CaptureResult {
        val reader = imageReader
            ?: return failure(Constants.REASON_NOT_READY, Constants.ERROR_NO_SERVICE, emit)

        var image: Image? = null
        try {
            image = reader.acquireLatestImage()
            if (image == null) {
                return failure("No frame available yet", Constants.ERROR_CAPTURE_FAILED, emit)
            }
            val full = imageToBitmap(image)
                ?: return failure("Could not decode frame", Constants.ERROR_CAPTURE_FAILED, emit)

            if (isEffectivelyBlank(full)) {
                full.recycle()
                // Black/empty frame: the target window almost certainly sets
                // FLAG_SECURE. Report honestly; do NOT attempt any bypass.
                return failure(Constants.REASON_FLAG_SECURE, Constants.ERROR_FLAG_SECURE, emit)
            }

            // Crop to the user's focus area (if one is set), so only the board
            // region is sent to the backend.
            val bitmap = cropToRegion(full)

            val file = saveBitmap(bitmap)
            val w = bitmap.width
            val h = bitmap.height
            bitmap.recycle()

            if (file == null) {
                return failure("Could not save capture", Constants.ERROR_CAPTURE_FAILED, emit)
            }

            if (emit) {
                SolverEventBus.emit(
                    Constants.EVENT_SCREENSHOT_CAPTURED,
                    mapOf(
                        Constants.KEY_PATH to file.absolutePath,
                        Constants.KEY_WIDTH to w,
                        Constants.KEY_HEIGHT to h,
                    ),
                )
            }
            return CaptureResult.Success(file.absolutePath, w, h)
        } catch (t: Throwable) {
            return failure(t.message ?: "Unexpected capture error", Constants.ERROR_CAPTURE_FAILED, emit)
        } finally {
            image?.close()
        }
    }

    /**
     * Crop [source] to the normalized [CaptureRegionHolder] region, if set and
     * valid. Returns a new bitmap (recycling [source]) when cropped, else the
     * source unchanged.
     */
    private fun cropToRegion(source: Bitmap): Bitmap {
        val region = CaptureRegionHolder.region ?: return source
        val left = (region.left * source.width).toInt().coerceIn(0, source.width - 1)
        val top = (region.top * source.height).toInt().coerceIn(0, source.height - 1)
        val right = (region.right * source.width).toInt().coerceIn(left + 1, source.width)
        val bottom = (region.bottom * source.height).toInt().coerceIn(top + 1, source.height)
        return runCatching {
            val cropped = Bitmap.createBitmap(source, left, top, right - left, bottom - top)
            if (cropped !== source) source.recycle()
            cropped
        }.getOrDefault(source)
    }

    private fun imageToBitmap(image: Image): Bitmap? {
        val planes = image.planes
        if (planes.isEmpty()) return null
        val plane = planes[0]
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * image.width
        val bitmapWidth = image.width + rowPadding / pixelStride

        val bitmap = Bitmap.createBitmap(
            bitmapWidth,
            image.height,
            Bitmap.Config.ARGB_8888,
        )
        bitmap.copyPixelsFromBuffer(buffer)

        // Crop away the row-stride padding so the saved frame is exactly the
        // display size.
        if (rowPadding == 0) return bitmap
        val cropped = Bitmap.createBitmap(bitmap, 0, 0, image.width, image.height)
        bitmap.recycle()
        return cropped
    }

    /**
     * Cheap blank/black detection: sample a grid of pixels; if every sample is
     * fully opaque black (or fully transparent), treat the frame as blocked.
     */
    private fun isEffectivelyBlank(bitmap: Bitmap): Boolean {
        val samplesPerAxis = 16
        val stepX = (bitmap.width / samplesPerAxis).coerceAtLeast(1)
        val stepY = (bitmap.height / samplesPerAxis).coerceAtLeast(1)
        var x = 0
        while (x < bitmap.width) {
            var y = 0
            while (y < bitmap.height) {
                val pixel = bitmap.getPixel(x, y)
                val alpha = (pixel ushr 24) and 0xFF
                val rgb = pixel and 0x00FFFFFF
                // A non-black, visible pixel means the frame has content.
                if (alpha != 0 && rgb != 0x000000) {
                    return false
                }
                y += stepY
            }
            x += stepX
        }
        return true
    }

    private fun saveBitmap(bitmap: Bitmap): File? {
        return runCatching {
            val dir = File(cacheDir, Constants.CAPTURE_DIR_NAME).apply { mkdirs() }
            // Unique name per capture so an in-flight upload of a previous frame
            // is never overwritten mid-read (which previously truncated the body
            // and produced "Request aborted" on the backend).
            val file = File(
                dir,
                "${Constants.CAPTURE_FILE_PREFIX}${System.currentTimeMillis()}${Constants.CAPTURE_FILE_EXT}",
            )
            // Vision models downscale internally before reading (OpenAI "high"
            // detail: fit in 2048px, then shortest side to 768px), so pixels
            // beyond that budget never reach the model — they only slow the
            // upload. Downscale to the same budget and encode JPEG (quality 92
            // keeps glyph edges crisp): a 1080x2400 lossless PNG of 1-5 MB
            // becomes a ~100-300 KB file with identical model-visible content.
            val scaled = scaleToVisionBudget(bitmap)
            FileOutputStream(file).use { out ->
                scaled.compress(Bitmap.CompressFormat.JPEG, Constants.CAPTURE_JPEG_QUALITY, out)
                out.flush()
            }
            if (scaled !== bitmap) scaled.recycle()
            pruneOldCaptures(dir, keep = file)
            file
        }.getOrNull()
    }

    /**
     * Scale [bitmap] down (never up) so the shortest side fits
     * [Constants.CAPTURE_MAX_SHORT_SIDE] and the longest side fits
     * [Constants.CAPTURE_MAX_LONG_SIDE], preserving aspect ratio. Returns the
     * original bitmap when it is already within budget.
     */
    private fun scaleToVisionBudget(bitmap: Bitmap): Bitmap {
        val short = minOf(bitmap.width, bitmap.height).toFloat()
        val long = maxOf(bitmap.width, bitmap.height).toFloat()
        val scale = minOf(
            Constants.CAPTURE_MAX_SHORT_SIDE / short,
            Constants.CAPTURE_MAX_LONG_SIDE / long,
            1f,
        )
        if (scale >= 1f) return bitmap
        val w = (bitmap.width * scale).toInt().coerceAtLeast(1)
        val h = (bitmap.height * scale).toInt().coerceAtLeast(1)
        return runCatching { Bitmap.createScaledBitmap(bitmap, w, h, true) }
            .getOrDefault(bitmap)
    }

    /** Keep only the most recent [Constants.CAPTURE_KEEP_FILES] capture files. */
    private fun pruneOldCaptures(dir: File, keep: File) {
        runCatching {
            val files = dir.listFiles { f ->
                f.isFile && f.name.startsWith(Constants.CAPTURE_FILE_PREFIX)
            } ?: return
            files
                .sortedByDescending { it.lastModified() }
                .drop(Constants.CAPTURE_KEEP_FILES)
                .forEach { old -> if (old != keep) old.delete() }
        }
    }

    private fun failure(reason: String, code: String, emit: Boolean): CaptureResult.Failure {
        if (emit) {
            SolverEventBus.emit(
                Constants.EVENT_SCREENSHOT_FAILED,
                mapOf(
                    Constants.KEY_REASON to reason,
                    Constants.KEY_CODE to code,
                ),
            )
        }
        return CaptureResult.Failure(reason, code)
    }

    // --- Foreground notification ---

    private fun startForegroundCompat() {
        createNotificationChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                Constants.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(Constants.NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(Constants.NOTIFICATION_CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            Constants.NOTIFICATION_CHANNEL_ID,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.notification_channel_description)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentPi = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
        return NotificationCompat.Builder(this, Constants.NOTIFICATION_CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(getString(R.string.notification_text))
            .setSmallIcon(R.drawable.ic_solver_notification)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .apply { contentPi?.let { setContentIntent(it) } }
            .build()
    }

    // --- Teardown ---

    private fun stopSelfSafely() {
        releaseResources()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun releaseResources() {
        started = false
        runCatching { virtualDisplay?.release() }
        virtualDisplay = null
        runCatching { imageReader?.close() }
        imageReader = null
        mediaProjection?.let {
            runCatching { it.unregisterCallback(projectionCallback) }
            runCatching { it.stop() }
        }
        mediaProjection = null
        captureThread?.let { thread ->
            runCatching { thread.quitSafely() }
        }
        captureThread = null
        captureHandler = null
        if (instance === this) instance = null
    }

    override fun onDestroy() {
        releaseResources()
        super.onDestroy()
    }

    /** Result of a single capture attempt. */
    sealed class CaptureResult {
        data class Success(val path: String, val width: Int, val height: Int) : CaptureResult()
        data class Failure(val reason: String, val code: String) : CaptureResult()
    }

    companion object {
        /** Static reference so the Activity/overlay can reach the live service. */
        @Volatile
        var instance: ScreenCaptureService? = null
            private set

        fun start(context: Context) {
            val intent = Intent(context, ScreenCaptureService::class.java).apply {
                action = Constants.ACTION_START_CAPTURE
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, ScreenCaptureService::class.java).apply {
                action = Constants.ACTION_STOP_CAPTURE
            }
            // Best-effort: route a stop action through onStartCommand.
            runCatching { context.startService(intent) }
            // Also stop directly in case the service is not accepting commands.
            runCatching { context.stopService(Intent(context, ScreenCaptureService::class.java)) }
        }

        /** Fire-and-forget single capture request via an intent action. */
        fun captureOnce(context: Context) {
            val live = instance
            if (live != null) {
                live.captureOnce()
                return
            }
            val intent = Intent(context, ScreenCaptureService::class.java).apply {
                action = Constants.ACTION_CAPTURE_ONCE
            }
            context.startForegroundService(intent)
        }
    }
}
