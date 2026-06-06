package com.codertapsu.xiangqi_solver

/**
 * Process-wide store for the user's optional capture focus area, expressed as
 * NORMALIZED fractions (0..1) of the screen so it survives rotation and applies
 * cleanly to any captured bitmap size. Null means "capture the whole screen".
 *
 * The selection UI writes here; [ScreenCaptureService] reads it when cropping.
 */
object CaptureRegionHolder {

    /** A normalized crop rectangle; all values are clamped to [0, 1]. */
    data class Region(val left: Float, val top: Float, val right: Float, val bottom: Float) {
        val isValid: Boolean
            get() = right - left > 0.02f && bottom - top > 0.02f
    }

    @Volatile
    var region: Region? = null
        private set

    val hasRegion: Boolean
        get() = region != null

    fun set(left: Float, top: Float, right: Float, bottom: Float) {
        val l = left.coerceIn(0f, 1f)
        val t = top.coerceIn(0f, 1f)
        val r = right.coerceIn(0f, 1f)
        val b = bottom.coerceIn(0f, 1f)
        val candidate = Region(minOf(l, r), minOf(t, b), maxOf(l, r), maxOf(t, b))
        region = if (candidate.isValid) candidate else null
    }

    fun clear() {
        region = null
    }
}
