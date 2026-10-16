import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing config from android/key.properties (gitignored). If absent
// (local dev / CI), release falls back to the debug keystore so the build still
// works — but you MUST create a real upload key before publishing. See
// docs/PUBLISHING.md.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.codertapsu.xiangqi_solver"
    // Compile against SDK 37: androidx.core 1.19 and receive_sharing_intent 1.9
    // declare a minimum compileSdk of 37 (the AAR-metadata check fails the build
    // below that). compileSdk only selects the APIs we compile against; runtime
    // behavior follows targetSdk below, which is deliberately independent.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // The on-device engine (jniLibs/<abi>/libpikafish.so) is an EXECUTABLE we
    // launch at runtime. Legacy packaging extracts native libs onto disk
    // (nativeLibraryDir), the only place Android allows exec — compressed,
    // in-APK libs can't be run. Equivalent to extractNativeLibs="true".
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    defaultConfig {
        applicationId = "com.codertapsu.xiangqi_solver"
        // TYPE_APPLICATION_OVERLAY (floating widget) requires API 26.
        minSdk = 26
        // Google Play requires API 36 (Android 16) for new apps and updates.
        // Audited against the Android 16 target-36 behavior changes: no
        // onBackPressed/KEYCODE_BACK handling (predictive back is on by
        // default), no edge-to-edge opt-out, no orientation locks, no
        // scheduleAtFixedRate. Re-audit before raising it further: local-network
        // protection (opt-in at 36, enforced in a later release) would gate the
        // LAN backends this app is pointed at during development.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the real upload key when key.properties is present, else the
            // debug key so local `flutter build` still works.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // R8 code + resource shrinking ON (smaller app + a mapping file that
            // resolves Play's "no deobfuscation file" warning). AGP 9 / R8 full
            // mode would otherwise strip Room's reflectively-loaded
            // WorkDatabase_Impl — pulled in via google_mobile_ads →
            // androidx.startup → WorkManager → Room — and the app would CRASH on
            // launch ("Failed to create an instance of
            // androidx.work.impl.WorkDatabase"). proguard-rules.pro keeps
            // WorkManager/Room/startup (+ Tink/Billing/Ads + the native bridge)
            // so the shrunk release runs. Release-only; debug never minifies.
            // VERIFY any plugin/dependency change with a real-device release
            // launch — a missing keep crashes only in the minified build.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            // Bundle native debug symbols (the Pikafish libpikafish.so and
            // friends) so Play can symbolicate native crashes/ANRs.
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }

        debug {
            // Give local/dev builds a separate applicationId so a debug build can
            // be installed SIDE-BY-SIDE with the Play release (which is signed by
            // Google's app-signing key — a different signer, so it can't be
            // replaced by a locally upload-key-signed build). The namespace is
            // unchanged, so the manifest's `.LauncherVi`/`.MainActivity` class
            // names stay under `com.codertapsu.xiangqi_solver` — the native
            // alias-switch resolves them against the namespace, not this id.
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.appcompat:appcompat:1.8.0")
}
