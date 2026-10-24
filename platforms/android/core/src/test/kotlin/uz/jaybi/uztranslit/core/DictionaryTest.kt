package uz.jaybi.uztranslit.core

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** UzDictionary must be SPEC §6, read from spec/SPEC.md itself (copied into the test resources at build time). */
class DictionaryTest {
    private fun specEntries(): List<Pair<String, String>> {
        val section = resourceText("SPEC.md").substringAfter("## 6.").substringBefore("## 7.")
        val block = section.substringAfter("```").substringBefore("```")
        return block.lines()
            .flatMap { it.split(" · ") }
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .map { entry ->
                val parts = entry.split(' ')
                check(parts.size == 2) { "unexpected SPEC §6 entry \"$entry\"" }
                parts[0] to parts[1]
            }
    }

    @Test
    fun `holds exactly the SPEC section 6 entries in SPEC order`() {
        val spec = specEntries()
        assertTrue(spec.size > 50, "could not read SPEC §6 (${spec.size} entries)")
        assertEquals(spec, UzDictionary.entries)
    }

    @Test
    fun `keys are unique lowercase ASCII`() {
        val keys = UzDictionary.entries.map { it.first }
        assertEquals(keys.size, keys.toSet().size, "duplicate keys")
        for (k in keys) assertTrue(k.all { it in 'a'..'z' || it == '\'' }, "key $k")
    }

    @Test
    fun `the longest key that is a prefix wins`() {
        assertEquals("sirkul", UzDictionary.longestPrefixOf("sirkulni"))
        assertEquals("sirk", UzDictionary.longestPrefixOf("sirklar"))
        assertEquals("kompyuter", UzDictionary.longestPrefixOf("kompyuterlar"))
        assertNull(UzDictionary.longestPrefixOf("sentabr")) // the SPEC keeps "sent" out on purpose
        assertNull(UzDictionary.longestPrefixOf("salom"))
        assertNull(UzDictionary.longestPrefixOf(""))
        assertNull(UzDictionary.longestPrefixOf("сирк"))
    }
}
