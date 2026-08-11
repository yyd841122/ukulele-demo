import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名:读 android/key.properties(该文件已被 .gitignore 排除,不会进 git)。
// 没有这个文件时(比如只是本地 debug 调试)就退回 debug 签名,不报错。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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

    signingConfigs {
        create("release") {
            // 只有 key.properties 存在且填了 storeFile 时才配正式签名。
            // 本地没配就什么都不做,release 会退回 debug 签名(不影响 flutter run --release)。
            if (keystoreProperties.containsKey("storeFile")) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // storeFile 路径相对 android/(根项目目录)解析,不是 android/app/。
                // key.properties 在 android/ 下,密钥库也在 android/ 下,两者对齐。
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 发布签名:配了 key.properties 就用正式密钥,否则退回 debug。
            signingConfig =
                if (keystoreProperties.containsKey("storeFile")) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
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
