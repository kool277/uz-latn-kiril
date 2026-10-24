package uz.jaybi.uztranslit.core

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import org.junit.jupiter.api.TestInstance

/**
 * Conformance runner for spec/fixtures.json, the contract every port must pass (SPEC: "a port is conformant when it
 * passes every entry in fixtures.json"). Same checks as core/js/test.js: every case with default options, every
 * roundtrip, every detection and every optional feature. One dynamic test per fixture entry.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class FixturesTest {
    private val fixtures: JsonObject = Json.parseToJsonElement(resourceText("fixtures.json")).jsonObject
    private val passed = AtomicInteger()

    private fun section(name: String): List<JsonObject> =
        fixtures[name]?.jsonArray?.map { it.jsonObject } ?: error("fixtures.json has no \"$name\" section")

    private fun check(name: String, body: () -> Unit): DynamicTest = dynamicTest(name) {
        body()
        passed.incrementAndGet()
    }

    @TestFactory
    fun cases(): List<DynamicTest> = section("cases").map { c ->
        check("${c.str("id")} ${c.str("from")}->${c.str("to")} ${show(c.str("in"))}") {
            assertEquals(c.str("out"), UzTranslit.convert(c.str("in"), c.str("from"), c.str("to")))
        }
    }

    @TestFactory
    fun roundtrips(): List<DynamicTest> = section("roundtrips").map { r ->
        check("${r.str("id")} ${r.str("from")}->${r.str("via")}->${r.str("from")}") {
            val there = UzTranslit.convert(r.str("in"), r.str("from"), r.str("via"))
            assertEquals(r.str("in"), UzTranslit.convert(there, r.str("via"), r.str("from")), "via $there")
        }
    }

    @TestFactory
    fun detect(): List<DynamicTest> = section("detect").map { d ->
        check("detect ${show(d.str("in"))}") {
            assertEquals(d.str("expect"), UzTranslit.detect(d.str("in")))
        }
    }

    @TestFactory
    fun optional(): List<DynamicTest> = section("optional").map { o ->
        check("optional/${o.str("feature")} ${show(o.str("in"))}") {
            val options = when (val feature = o.str("feature")) {
                "asciiApostrophe" -> UzTranslit.Options(okina = "'", tutuq = "'")
                "skipUrls" -> UzTranslit.Options(skipUrls = true)
                else -> error("unknown optional feature \"$feature\": teach FixturesTest about it")
            }
            assertEquals(o.str("out"), UzTranslit.convert(o.str("in"), o.str("from"), o.str("to"), options))
        }
    }

    @Test
    fun `fixtures and the engine agree on the apostrophes`() {
        val marks = fixtures["apostrophes"]!!.jsonObject
        assertEquals(UzTranslit.OKINA, marks.str("okina"))
        assertEquals(UzTranslit.TUTUQ, marks.str("tutuq"))
    }

    @Test
    fun `every section has entries`() {
        for (name in listOf("cases", "roundtrips", "detect", "optional")) {
            assertTrue(section(name).isNotEmpty(), "fixtures.json \"$name\" is empty")
        }
    }

    @AfterAll
    fun summary() {
        val sizes = listOf("cases", "roundtrips", "detect", "optional").associateWith { section(it).size }
        println(
            "FixturesTest: ${passed.get()}/${sizes.values.sum()} fixture checks passed " +
                "(${sizes.entries.joinToString { "${it.value} ${it.key}" }}; spec/fixtures.json v${fixtures.str("version")})",
        )
    }
}
