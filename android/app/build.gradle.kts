import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Huawei agconnect plugin — processes agconnect-services.json for HMS Core.
    id("com.huawei.agconnect")
    id("com.hihonor.mcs.asplugin")
}

configurations.all {
    exclude(group = "com.android.support", module = "support-compat")
    // Avoid dexing huge compose icon artifacts that may trigger OOM on low-memory dev machines.
    exclude(group = "androidx.compose.material", module = "material-icons-extended-android")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.tianyanzhiyun.emergency_helper"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.tianyanzhiyun.emergency_helper"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        multiDexEnabled = true
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // TIMPush vendor channel placeholders (configured via timpush-configs.json from IM console).
        // vivo / honor need these for build-time validation.
        manifestPlaceholders["VIVO_APPKEY"] = ""
        manifestPlaceholders["VIVO_APPID"] = ""
        manifestPlaceholders["HONOR_APPID"] = "104559484"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        debug {
            // Keep debug experience, but use release keystore so vendor push
            // (Huawei/TIMPush) signature checks match console configuration.
            signingConfig = signingConfigs.getByName("release")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // TIMPush core — needed for direct access to TIMPushManager/Listener in MainApplication.
    implementation("com.tencent.timpush:timpush:8.9.7537")
    // TIMPush vendor channels — add/remove based on your target devices.
    // These are TIMPush modules that hook into the native push SDKs.
    // On Honor devices (brand 2001), TIMPush auto-routes to Huawei channel.
    implementation("com.tencent.timpush:huawei:8.9.7537")
    implementation("com.tencent.timpush:xiaomi:8.9.7537")
    implementation("com.tencent.timpush:vivo:8.9.7537")
    implementation("com.tencent.timpush:honor:8.9.7537")
    implementation("com.tencent.timpush:oppo:8.9.7537")
    // implementation("com.tencent.timpush:meizu:8.9.7537")
    // implementation("com.tencent.timpush:fcm:8.9.7537")
}
