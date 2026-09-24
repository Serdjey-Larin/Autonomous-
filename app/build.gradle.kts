plugins {
    id("com.android.application") version "8.1.4"
}

android {
    namespace = "com.example.autonomouseye"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.example.autonomouseye"
        minSdk = 26
        targetSdk = 34
        versionCode = 7
        versionName = "1.7"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    packagingOptions {
        resources.excludes.add("META-INF/*")
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("org.videolan.android:libvlc-all:3.6.0")
    implementation("com.google.mlkit:image-labeling:17.0.8")
    implementation("com.google.mlkit:face-detection:16.1.7")
    implementation("com.github.hannesa2:paho.mqtt.android:4.3.beta2")
implementation("com.arthenica:ffmpeg-kit-min:6.0-2")
}
