package com.codertapsu.xiangqi_solver

import android.content.Intent

/**
 * Stores the result of the OFFICIAL MediaProjection consent dialog so that the
 * [ScreenCaptureService] can build the projection later.
 *
 * The granted `Intent` is only valid for a single MediaProjection; we keep a
 * reference (not a token copy) and clear it on stop to avoid leaking the consent
 * across solver sessions. This holder never fakes or persists consent — it only
 * caches the exact result the user explicitly approved.
 */
object MediaProjectionHolder {

    @Volatile
    var resultCode: Int = Int.MIN_VALUE
        private set

    @Volatile
    var resultData: Intent? = null
        private set

    /** True only when the user has granted capture in this session. */
    val hasConsent: Boolean
        get() = resultData != null && resultCode != Int.MIN_VALUE

    @Synchronized
    fun store(code: Int, data: Intent) {
        resultCode = code
        resultData = data
    }

    @Synchronized
    fun clear() {
        resultCode = Int.MIN_VALUE
        resultData = null
    }
}
