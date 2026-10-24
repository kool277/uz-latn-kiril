package uz.jaybi.uztranslit.core

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonPrimitive

/**
 * Test data copied from the repository by the copyConformanceData Gradle task (core/build.gradle.kts):
 * spec/fixtures.json, spec/SPEC.md and, when it has been generated, build/differential.json.
 */
internal fun resourceTextOrNull(name: String): String? =
    TestDataMarker::class.java.getResourceAsStream("/$name")?.use { it.readBytes().toString(Charsets.UTF_8) }

internal fun resourceText(name: String): String =
    resourceTextOrNull(name) ?: error("test resource $name is missing: the copyConformanceData task copies it")

private object TestDataMarker

internal fun JsonObject.str(key: String): String = this[key]?.jsonPrimitive?.content ?: error("missing \"$key\" in $this")

internal fun JsonObject.bool(key: String): Boolean = this[key]?.jsonPrimitive?.boolean ?: error("missing \"$key\" in $this")

/** A string with everything outside printable ASCII written as \uXXXX escapes, so failures show invisible characters. */
internal fun show(s: String): String = buildString {
    append('"')
    for (c in s) {
        if (c in ' '..'~' && c != '"' && c != '\\') append(c) else append("\\u%04x".format(c.code))
    }
    append('"')
}
