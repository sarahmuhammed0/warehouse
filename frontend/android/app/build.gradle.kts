import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, read from android/key.properties when it exists.
//
// That file holds a password, so it is gitignored (along with *.jks/*.keystore)
// and never committed. See docs/deployment.md, "Building the Android app".
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.warehouseos.warehouse_os_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.warehouseos.warehouse_os_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
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
            // A real key when one is configured; the debug key otherwise.
            //
            // Falling back rather than failing is deliberate: `flutter build apk
            // --release` has to keep working on a machine with no keystore, which
            // is how it is built for internal testing. But a debug-signed APK
            // cannot go to the Play Store, and swapping to a real key later
            // forces every existing install to be uninstalled first — different
            // signature, no upgrade path. So the fallback announces itself
            // instead of being a silent default nobody notices until release day.
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
                // println as well as logger.warn: Flutter filters most of
                // Gradle's output, and a warning nobody sees is the thing this
                // whole branch exists to prevent.
                val notice =
                    "\n[warehouse-os] Release APK is signed with the DEBUG key — " +
                        "android/key.properties was not found.\n" +
                        "[warehouse-os] Fine for internal testing. NOT publishable, and a later " +
                        "switch to a real key means every install must be removed first.\n" +
                        "[warehouse-os] See docs/deployment.md, \"Building the Android app\".\n"
                println(notice)
                logger.warn(notice)
            }
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
