plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningEnvironment = mapOf(
    "ANDROID_RELEASE_KEYSTORE_PATH" to providers.environmentVariable("ANDROID_RELEASE_KEYSTORE_PATH").orNull,
    "ANDROID_RELEASE_STORE_PASSWORD" to providers.environmentVariable("ANDROID_RELEASE_STORE_PASSWORD").orNull,
    "ANDROID_RELEASE_KEY_ALIAS" to providers.environmentVariable("ANDROID_RELEASE_KEY_ALIAS").orNull,
    "ANDROID_RELEASE_KEY_PASSWORD" to providers.environmentVariable("ANDROID_RELEASE_KEY_PASSWORD").orNull,
)
val releaseSigningConfigured = releaseSigningEnvironment.values.all { !it.isNullOrBlank() }

android {
    namespace = "com.bernoulli.trailrunner.trail_runner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Stable update identity. Changing this value creates a different app.
        applicationId = "com.bernoulli.trailrunner.trail_runner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(releaseSigningEnvironment.getValue("ANDROID_RELEASE_KEYSTORE_PATH")!!)
                storePassword = releaseSigningEnvironment.getValue("ANDROID_RELEASE_STORE_PASSWORD")
                keyAlias = releaseSigningEnvironment.getValue("ANDROID_RELEASE_KEY_ALIAS")
                keyPassword = releaseSigningEnvironment.getValue("ANDROID_RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

val validateReleaseSigning by tasks.registering {
    group = "verification"
    description = "Fails when Android release-signing credentials are incomplete."
    doLast {
        val missingVariables = releaseSigningEnvironment
            .filterValues { it.isNullOrBlank() }
            .keys
        if (missingVariables.isNotEmpty()) {
            throw GradleException(
                "Android release signing is not configured. Missing: ${missingVariables.joinToString()}",
            )
        }

        val keystorePath = releaseSigningEnvironment.getValue("ANDROID_RELEASE_KEYSTORE_PATH")!!
        if (!file(keystorePath).isFile) {
            throw GradleException("Android release keystore does not exist: $keystorePath")
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(validateReleaseSigning)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
