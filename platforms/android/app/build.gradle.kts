import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// AGP 9 compiles the Kotlin sources itself (built-in Kotlin): only the Compose compiler plugin is applied here.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "uz.jaybi.uztranslit"
    compileSdk = 37

    defaultConfig {
        applicationId = "uz.jaybi.uztranslit"
        minSdk = 24
        targetSdk = 37
        versionCode = 5
        versionName = "1.4.0"
    }

    // The upload key for Google Play (Play App Signing re-signs for users); README.md ▸ Signing. Only from the
    // environment, never from the repository: CI decodes it from secrets. Without it, release builds are unsigned.
    val uploadStore = System.getenv("UZT_UPLOAD_STORE_FILE")
    signingConfigs {
        if (!uploadStore.isNullOrEmpty()) {
            create("upload") {
                storeFile = file(uploadStore)
                storeType = "PKCS12"
                storePassword = System.getenv("UZT_UPLOAD_STORE_PASSWORD")
                keyAlias = System.getenv("UZT_UPLOAD_KEY_ALIAS") ?: "upload"
                keyPassword = System.getenv("UZT_UPLOAD_STORE_PASSWORD")   // PKCS12: one password for store and key
            }
        }
    }

    buildTypes {
        release {
            signingConfigs.findByName("upload")?.let { signingConfig = it }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    androidResources {
        // English (default), Uzbek and Russian only; also generates the locale config for per-app languages
        localeFilters += listOf("en", "uz", "ru")
        generateLocaleConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

dependencies {
    implementation(project(":core"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.datastore.preferences)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.kotlinx.coroutines.test)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
    testLogging {
        events("skipped", "failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
