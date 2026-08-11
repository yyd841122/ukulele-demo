plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.youyd.ukulele"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 需要 core library desugaring(第58步-4)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 应用包名(applicationId):Play Store 终身唯一标识,发布后不可改。
        // (从模板默认值 com.example.ukulele_demo 改成自己的,Google Play 禁止 com.example 前缀。)
        applicationId = "app.youyd.ukulele"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // soundpool 依赖的 AndroidX 库要求 minSdk ≥ 21,这里显式设到 24 满足它们。
        // (荣耀300 是 Android 16,毫无影响;只是不再支持 Android 7 以下的老机器。)
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // flutter_local_notifications 要求 multiDexEnabled(第58步-4)
        multiDexEnabled = true
    }

    dependencies {
        // flutter_local_notifications 需要 core library desugaring(第58步-4)
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
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
