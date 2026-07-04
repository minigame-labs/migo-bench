plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "com.migo.bench.migo"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.migo.bench.migo"
        minSdk = 26          // migo runtime AAR pins minSdk 26 (Skia/NDK Oreo baseline)
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release { isMinifyEnabled = false }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    implementation(files("libs/migo.aar"))
}
