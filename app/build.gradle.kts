```kotlin
plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.autonomouseye"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.example.autonomouseye"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
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
}
```
