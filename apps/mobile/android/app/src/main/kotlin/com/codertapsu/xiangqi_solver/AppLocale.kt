package com.codertapsu.xiangqi_solver

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * The in-app "App language" setting, for the native UI Flutter doesn't draw:
 * the floating overlay, the capture-area selector and the Solver Mode
 * notification. Left alone they follow the SYSTEM locale, so a phone set to
 * English showed "Red" beside a Vietnamese app.
 *
 * Flutter's shared_preferences (legacy API, see lib/main.dart) keeps the
 * setting in the "FlutterSharedPreferences" file with a "flutter." prefix:
 * "system" (follow the phone), "vi" or "en".
 */
object AppLocale {
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY = "flutter.settings.appLanguage"

    /** [base] with its resources in the app language ("system" → [base] itself). */
    fun wrap(base: Context): Context {
        val tag = runCatching {
            base.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
        }.getOrNull()
        if (tag.isNullOrBlank() || tag == "system") return base
        val config = Configuration(base.resources.configuration)
        config.setLocale(Locale.forLanguageTag(tag))
        return base.createConfigurationContext(config)
    }
}
