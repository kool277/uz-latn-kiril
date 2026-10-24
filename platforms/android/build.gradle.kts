// Plugin versions live in gradle/libs.versions.toml. AGP 9 compiles Kotlin itself (built-in Kotlin), so the app
// module applies no Kotlin Android plugin; declaring the Kotlin plugins here puts the catalogue's Kotlin Gradle
// plugin version on the build classpath shared by both modules.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
}
