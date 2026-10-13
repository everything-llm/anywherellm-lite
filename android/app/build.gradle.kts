import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The UnifiedPush connector brings Tink for the JVM, and flutter_secure_storage brings Tink for
// Android, which holds the same classes; the app keeps the Android one alone.
configurations.all {
    val tink = "com.google.crypto.tink:tink-android:1.23.0"
    resolutionStrategy {
        force(tink)
        dependencySubstitution {
            substitute(module("com.google.crypto.tink:tink")).using(module(tink))
        }
    }
}

// Release signing is read from android/key.properties, which is gitignored; `appstore sync`
// writes it the first time it builds this app. Android keys an installed app to its signing
// certificate, so the first key to publish local.anywherellm.lite must sign every later
// update -- which is why a missing key.properties fails the release build instead of falling
// back to the debug keystore.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "local.anywherellm.anywherellm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "local.anywherellm.lite"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Left unset when there is no key: the failure below is raised when a release is
            // assembled, not while the project is configured, so `flutter run` still builds.
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

if (!hasReleaseKey) {
    tasks.matching { it.name == "assembleRelease" || it.name == "bundleRelease" }
        .configureEach {
            doFirst {
                throw GradleException(
                    "android/key.properties is missing, so this release build has no signing " +
                    "key. Publishing debug-signed would tie every future update of " +
                    "local.anywherellm.lite to ~/.android/debug.keystore. Run " +
                    "`appstore sync`, which writes it, or create it with storeFile, " +
                    "storePassword, keyAlias and keyPassword."
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

dependencies {
    // PushEvents hands the distributor's events to the UnifiedPush plugin's flow, whose
    // coroutines the plugin keeps to itself.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
}
