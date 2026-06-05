package com.xiangqisolver.xiangqi_solver

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle

/**
 * A transparent, throwaway activity whose only job is to display the OFFICIAL
 * Android MediaProjection consent dialog and report the outcome.
 *
 * We never bypass or fake this dialog. The user must explicitly approve screen
 * capture; only on RESULT_OK do we store the consent in [MediaProjectionHolder].
 *
 * The result is reported back to the caller through [ResultBridge] because the
 * caller (MainActivity's MethodChannel handler) needs the boolean to resolve a
 * pending Flutter Result. A static bridge keeps the two activities decoupled.
 */
class MediaProjectionPermissionActivity : Activity() {

    /** Decouples this activity from whoever is waiting for the consent result. */
    object ResultBridge {
        @Volatile
        private var callback: ((Boolean) -> Unit)? = null

        fun setCallback(cb: (Boolean) -> Unit) {
            callback = cb
        }

        fun deliver(granted: Boolean) {
            val cb = callback
            callback = null
            cb?.invoke(granted)
        }
    }

    private var launched = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) {
            // Recreated after a config change while the dialog was up; wait for
            // onActivityResult instead of launching a second dialog.
            launched = savedInstanceState.getBoolean(STATE_LAUNCHED, false)
        }
        if (!launched) {
            launchConsentDialog()
        }
    }

    private fun launchConsentDialog() {
        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
        if (manager == null) {
            finishWithResult(false)
            return
        }
        launched = true
        // createScreenCaptureIntent() is the only sanctioned way to request
        // capture. It always shows the system consent UI.
        startActivityForResult(
            manager.createScreenCaptureIntent(),
            Constants.REQUEST_MEDIA_PROJECTION,
        )
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean(STATE_LAUNCHED, launched)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != Constants.REQUEST_MEDIA_PROJECTION) {
            finishWithResult(false)
            return
        }
        val granted = resultCode == RESULT_OK && data != null
        if (granted) {
            MediaProjectionHolder.store(resultCode, data!!)
        }
        finishWithResult(granted)
    }

    private fun finishWithResult(granted: Boolean) {
        ResultBridge.deliver(granted)
        finish()
        // Suppress activity transition so the consent flow feels instantaneous.
        overridePendingTransition(0, 0)
    }

    private companion object {
        const val STATE_LAUNCHED = "media_projection_launched"
    }
}
