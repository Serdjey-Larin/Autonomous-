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
        versionCode = 3
        versionName = "1.2"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("org.videolan.android:libvlc-all:3.6.0")
}
