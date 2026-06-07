# R8 / ProGuard keep rules for the release build.
#
# The Flutter Gradle plugin already injects the core Flutter/embedding rules;
# everything below covers THIS app's (mostly transitive) dependencies that
# break under R8 "full mode" (the AGP 9 default), which is more aggressive than
# classic ProGuard and ignores some library consumer rules.

-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod, Exceptions

# ── WorkManager + Room ───────────────────────────────────────────────────────
# Pulled in transitively: google_mobile_ads → androidx.startup → WorkManager →
# Room. Without these, R8 full mode strips the reflectively-loaded
# androidx.work.impl.WorkDatabase_Impl and the app CRASHES on launch
# ("Failed to create an instance of androidx.work.impl.WorkDatabase").
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep @androidx.room.Database class * { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**

# ── androidx.startup (runs initializers at app launch) ───────────────────────
-keep class androidx.startup.** { *; }
-keep class * extends androidx.startup.Initializer { *; }

# ── Tink / Jetpack Security ──────────────────────────────────────────────────
# persistent_device_id stores its fallback id in EncryptedSharedPreferences,
# and flutter_secure_storage uses the AndroidX security/crypto stack — both lean
# on Tink, which loads key managers reflectively.
-keep class com.google.crypto.tink.** { *; }
-keep class androidx.security.crypto.** { *; }
-dontwarn com.google.crypto.tink.**
-dontwarn javax.annotation.**

# ── Google Play Billing (in_app_purchase) ────────────────────────────────────
-keep class com.android.billingclient.api.** { *; }

# ── Google Mobile Ads (google_mobile_ads) ────────────────────────────────────
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.**

# ── This app's native bridge (method channels resolve by name) ───────────────
-keep class com.codertapsu.xiangqi_solver.** { *; }
