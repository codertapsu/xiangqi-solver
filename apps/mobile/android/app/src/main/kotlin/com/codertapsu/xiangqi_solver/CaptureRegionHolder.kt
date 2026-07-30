package com.codertapsu.xiangqi_solver

import android.content.Context
import android.content.SharedPreferences

/**
 * Store for the user's optional capture focus area, expressed as NORMALIZED
 * fractions (0..1) of the screen so it survives rotation and applies cleanly to
 * any captured bitmap size. Null means "capture the whole screen".
 *
 * The selection UI writes here; [ScreenCaptureService] reads it when cropping.
 *
 * The value is PERSISTED to SharedPreferences, so the last selected area is
 * restored after the process dies (swipe-away, low-memory kill, reboot) instead
 * of falling back to the default box. An in-memory copy is kept as a cache so
 * the hot read in [ScreenCaptureService] stays allocation-free.
 *
 * Every entry point takes a [Context] because this is a context-free `object`
 * and the components that touch it (an Activity, two Services, and the overlay
 * View) may each be the one that starts the process — there is no Application
 * subclass, and a service restarted by the system can run with no Activity at
 * all. The context is immediately normalized to `applicationContext`, so an
 * Activity/Service instance can never be captured by this singleton.
 */
object CaptureRegionHolder {

    private const val PREFS_NAME = "capture_region_prefs"
    private const val KEY_HAS_REGION = "has_region"
    private const val KEY_LEFT = "left"
    private const val KEY_TOP = "top"
    private const val KEY_RIGHT = "right"
    private const val KEY_BOTTOM = "bottom"

    /** A normalized crop rectangle; all values are clamped to [0, 1]. */
    data class Region(val left: Float, val top: Float, val right: Float, val bottom: Float) {
        val isValid: Boolean
            get() = right - left > 0.02f && bottom - top > 0.02f
    }

    @Volatile
    private var cached: Region? = null

    /** False until the persisted value has been read once for this process. */
    @Volatile
    private var loaded = false

    /**
     * Warm the cache off the persisted value. Idempotent and safe to call from
     * any component's `onCreate`; doing so keeps the first read off a
     * latency-sensitive path (the overlay seeds its box during a layout pass).
     */
    fun init(context: Context) {
        ensureLoaded(context)
    }

    /** The saved region, or null for "whole screen". */
    fun region(context: Context): Region? {
        ensureLoaded(context)
        return cached
    }

    fun hasRegion(context: Context): Boolean = region(context) != null

    /**
     * Save a selection. A rectangle that is too small to be usable is rejected
     * exactly as before — it stores "no region" (i.e. full screen) rather than
     * an unusable crop.
     */
    fun set(context: Context, left: Float, top: Float, right: Float, bottom: Float) {
        val l = left.coerceIn(0f, 1f)
        val t = top.coerceIn(0f, 1f)
        val r = right.coerceIn(0f, 1f)
        val b = bottom.coerceIn(0f, 1f)
        val candidate = Region(minOf(l, r), minOf(t, b), maxOf(l, r), maxOf(t, b))
        store(context, if (candidate.isValid) candidate else null)
    }

    /** Forget the focus area — subsequent captures use the whole screen. */
    fun clear(context: Context) {
        store(context, null)
    }

    /**
     * Update the cache and write through to disk. Both happen under the lock so
     * two writes can never land in the opposite order in memory and on disk.
     */
    private fun store(context: Context, value: Region?) {
        synchronized(this) {
            cached = value
            // Mark loaded: the cache is now authoritative, so a later read must
            // NOT overwrite this fresh value with what is still on disk.
            loaded = true
            // apply() updates the in-memory prefs map immediately (so a read on
            // any thread sees it) and flushes to disk asynchronously — commit()
            // would fsync on the calling thread, and every write site here is a
            // button click / platform-channel call on the main thread.
            prefs(context).edit().apply {
                if (value == null) {
                    putBoolean(KEY_HAS_REGION, false)
                    remove(KEY_LEFT)
                    remove(KEY_TOP)
                    remove(KEY_RIGHT)
                    remove(KEY_BOTTOM)
                } else {
                    putBoolean(KEY_HAS_REGION, true)
                    putFloat(KEY_LEFT, value.left)
                    putFloat(KEY_TOP, value.top)
                    putFloat(KEY_RIGHT, value.right)
                    putFloat(KEY_BOTTOM, value.bottom)
                }
            }.apply()
        }
    }

    /** Read the persisted value once per process (double-checked locking). */
    private fun ensureLoaded(context: Context) {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            cached = readPersisted(prefs(context))
            loaded = true
        }
    }

    private fun readPersisted(prefs: SharedPreferences): Region? {
        if (!prefs.getBoolean(KEY_HAS_REGION, false)) return null
        val restored = Region(
            prefs.getFloat(KEY_LEFT, 0f),
            prefs.getFloat(KEY_TOP, 0f),
            prefs.getFloat(KEY_RIGHT, 0f),
            prefs.getFloat(KEY_BOTTOM, 0f),
        )
        // Re-validate: a partially written or hand-edited prefs file must never
        // yield a degenerate crop that would break the capture.
        return if (restored.isValid) restored else null
    }

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
