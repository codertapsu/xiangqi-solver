plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.xiangqisolver.xiangqi_solver"
    // Compile against SDK 36: the AndroidX libraries Flutter resolves
    // (activity 1.12.x, core 1.18.x) require compileSdk >= 36. SDK 36 is
    // installed in this environment. targetSdk stays at 35 per the contract,
    // since compileSdk and targetSdk are independent knobs.
    compileSdk = 36
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
        applicationId = "com.xiangqisolver.xiangqi_solver"
        // TYPE_APPLICATION_OVERLAY (floating widget) requires API 26.
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
}
