package uz.jaybi.uztranslit.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance

/**
 * Differential test against the reference implementation: build/differential.json holds random texts (all three
 * alphabets, every apostrophe, JavaScript whitespace and look-alikes, URL/e-mail/handle fragments, emoji) converted
 * by core/js/uztranslit.js in every direction with random options, plus detections. Generate it in the repository
 * root with `node tools/make_differential.mjs` (CI does); without it this test is skipped.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class DifferentialTest {
    private val corpus: JsonObject? by lazy {
        resourceTextOrNull("differential.json")?.let { Json.parseToJsonElement(it).jsonObject }
    }

    private fun corpus(): JsonObject {
        val c = corpus
        assumeTrue(c != null) {
            "build/differential.json not found: run `node tools/make_differential.mjs` in the repository root " +
                "to enable the differential test against core/js/uztranslit.js"
        }
        return c!!
    }

    private fun options(o: JsonObject) = UzTranslit.Options(
        okina = o.str("okina"),
        tutuq = o.str("tutuq"),
        dropHardSignAfterO = o.bool("dropHardSignAfterO"),
        tsFinal = o.bool("tsFinal"),
        dictionary = o.bool("dictionary"),
        skipUrls = o.bool("skipUrls"),
    )

    @Test
    fun `conversions are identical to the reference`() {
        val root = corpus()
        val cases = root["cases"]!!.jsonArray
        val failures = mutableListOf<String>()
        var mismatches = 0
        for ((k, element) in cases.withIndex()) {
            val c = element.jsonObject
            val input = c.str("in")
            val want = c.str("out")
            val got = UzTranslit.convert(input, c.str("from"), c.str("to"), options(c["options"]!!.jsonObject))
            if (got != want) {
                mismatches++
                if (failures.size < 20) {
                    failures += "#$k ${c.str("from")}->${c.str("to")} ${c["options"]}\n   in   ${show(input)}\n" +
                        "   want ${show(want)}\n   got  ${show(got)}"
                }
            }
        }
        println(
            "DifferentialTest: ${cases.size - mismatches}/${cases.size} conversions identical to " +
                "${root.str("reference")} (seed ${root["seed"]})",
        )
        assertTrue(cases.isNotEmpty(), "differential.json has no cases")
        assertEquals(0, mismatches, "$mismatches conversions differ from the reference:\n" + failures.joinToString("\n"))
    }

    @Test
    fun `detections are identical to the reference`() {
        val root = corpus()
        val detections = root["detect"]!!.jsonArray
        val failures = mutableListOf<String>()
        var mismatches = 0
        for ((k, element) in detections.withIndex()) {
            val d = element.jsonObject
            val got = UzTranslit.detect(d.str("in"))
            if (got != d.str("expect")) {
                mismatches++
                if (failures.size < 20) failures += "#$k ${show(d.str("in"))}: want ${d.str("expect")}, got $got"
            }
        }
        println("DifferentialTest: ${detections.size - mismatches}/${detections.size} detections identical")
        assertTrue(detections.isNotEmpty(), "differential.json has no detections")
        assertEquals(0, mismatches, "$mismatches detections differ from the reference:\n" + failures.joinToString("\n"))
    }
}
