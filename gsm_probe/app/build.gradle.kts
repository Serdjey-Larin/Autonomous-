plugins {
    id("com.android.application")
}

android {
    namespace = "ru.larincold.gsmprobe"
    compileSdk = 36

    defaultConfig {
        applicationId = "ru.larincold.gsmprobe"
        minSdk = 26
        targetSdk = 36
        versionCode = (System.getenv("PROBE_VERSION_CODE") ?: "1").toInt()
        versionName = "0.1." + (System.getenv("PROBE_VERSION_CODE") ?: "1")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            val ks = System.getenv("LARIN_KEYSTORE_PATH")
            if (!ks.isNullOrBlank()) {
                storeFile = file(ks)
                storePassword = System.getenv("LARIN_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("LARIN_KEY_ALIAS")
                keyPassword = System.getenv("LARIN_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (System.getenv("LARIN_KEYSTORE_PATH").isNullOrBlank())
                signingConfigs.getByName("debug") else signingConfigs.getByName("release")
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
