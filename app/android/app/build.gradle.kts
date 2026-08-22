import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is configured from android/key.properties, which is never committed — see
// key.properties.example. Absent it, release builds fall back to the debug key, so a contributor
// with no keystore can still `flutter run --release` and still build an APK to try on a phone.
//
// Present but incomplete is a different thing entirely, and it fails the build rather than falling
// back. The failure this guards is the expensive one: a CI secret that did not decode leaves a
// truncated key.properties behind, and a silent fallback would publish a debug-signed APK to a
// GitHub release. Android refuses to install that over a properly signed one, so every existing
// user's update would break, and nothing would have gone red to say so.
val keystoreConfig = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystoreConfig.exists()) keystoreConfig.inputStream().use { load(it) }
}
val releaseKeystore = keystoreProperties.getProperty("storeFile")
    // Resolved against android/, where key.properties lives, so a relative path in it means what
    // somebody writing that file would expect. An absolute path is passed through unchanged.
    ?.let { rootProject.file(it) }

if (keystoreConfig.exists()) {
    val missing = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    require(missing.isEmpty()) {
        "android/key.properties is missing: ${missing.joinToString(", ")}"
    }
    require(releaseKeystore!!.exists()) {
        "android/key.properties points at a keystore that is not there: $releaseKeystore"
    }
}

val hasReleaseKeystore = releaseKeystore != null

android {
    namespace = "fm.chordia.mobile"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "fm.chordia.mobile"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        // The flavours set app_name through resValue.
        resValues = true
    }

    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Chordia Dev")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Chordia")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = releaseKeystore
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
