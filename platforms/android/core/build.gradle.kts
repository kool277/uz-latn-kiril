import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// The conversion engine: pure Kotlin/JVM, no Android dependencies (a port of spec/SPEC.md §5).
plugins {
    alias(libs.plugins.kotlin.jvm)
}

java {
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
}

kotlin {
    explicitApi()
    compilerOptions {
        jvmTarget = JvmTarget.JVM_21
    }
}

dependencies {
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.kotlinx.serialization.json)
    testRuntimeOnly(libs.junit.platform.launcher)
}

// The conformance data is never copied into the source tree by hand: this task copies it from the repository at
// build time. spec/fixtures.json and spec/SPEC.md are required; build/differential.json (written by
// `node tools/make_differential.mjs`) is optional and DifferentialTest is skipped when it is absent.
val repositoryRoot = rootProject.layout.projectDirectory.dir("../..")
val copyConformanceData = tasks.register<Sync>("copyConformanceData") {
    description = "Copies spec/fixtures.json, spec/SPEC.md and build/differential.json into the test resources."
    from(repositoryRoot.file("spec/fixtures.json"))
    from(repositoryRoot.file("spec/SPEC.md"))
    from(repositoryRoot.file("build/differential.json")) // a missing file is skipped (and removed by Sync)
    into(layout.buildDirectory.dir("generated/conformance"))
}

sourceSets {
    test {
        resources.srcDir(copyConformanceData)
    }
}

tasks.test {
    useJUnitPlatform()
    maxHeapSize = "1g"
    testLogging {
        events("skipped", "failed")
        showStandardStreams = true
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
