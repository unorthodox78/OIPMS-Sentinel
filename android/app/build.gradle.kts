// android/app/build.gradle.kts

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.oip_sentinel"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
        freeCompilerArgs += listOf("-Xlint:-options", "-Xlint:deprecation")
    }

    defaultConfig {
        applicationId = "com.example.oip_sentinel"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Flavors to install dashboard and camera apps side-by-side
    flavorDimensions += "app"
    productFlavors {
        create("dashboard") {
            dimension = "app"
        }
        create("camera") {
            dimension = "app"
            applicationIdSuffix = ".camera"
        }
    }
}

tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
    options.compilerArgs.addAll(listOf("-Xlint:-options", "-Xlint:deprecation"))
}

flutter {
    source = "../.."
}
