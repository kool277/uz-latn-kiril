package uz.jaybi.uztranslit.core

import java.util.Locale
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/** The public API around the scanners (the conversion rules themselves are checked by the fixtures). */
class UzTranslitTest {
    @Test
    fun `options default to the SPEC defaults`() {
        val o = UzTranslit.Options()
        assertEquals("\u02BB", o.okina)
        assertEquals("\u02BC", o.tutuq)
        assertEquals(listOf(true, true, true, true), listOf(o.dropHardSignAfterO, o.tsFinal, o.dictionary, o.skipUrls))
        assertEquals(o, UzTranslit.Options.DEFAULT)
        assertEquals(UzTranslit.Options(okina = "'", tutuq = "'"), UzTranslit.Options.ASCII)
    }

    @Test
    fun `okina and tutuq are empty or one character`() {
        UzTranslit.Options(okina = "", tutuq = "")
        assertThrows<IllegalArgumentException> { UzTranslit.Options(okina = "''") }
        assertThrows<IllegalArgumentException> { UzTranslit.Options(tutuq = "ab") }
    }

    @Test
    fun `same source and target return the text itself`() {
        val text = "Toshkent shahri"
        assertSame(text, UzTranslit.convert(text, "lat", "lat"))
        assertSame(text, UzTranslit.convert(text, "auto", "lat"))
    }

    @Test
    fun `auto detects the source`() {
        assertEquals("Toshkent shahri", UzTranslit.convert("Тошкент шаҳри", "auto", "lat"))
        assertEquals("Ўзбекистон", UzTranslit.convert("Özbekiston", "auto", "cyr"))
    }

    @Test
    fun `unknown directions are rejected`() {
        assertThrows<IllegalArgumentException> { UzTranslit.convert("x", "lat", "xyz") }
        assertThrows<IllegalArgumentException> { UzTranslit.convert("x", "auto", "auto") }
        assertThrows<IllegalArgumentException> { UzTranslit.convert("x", "cyr", "auto") }
    }

    @Test
    fun `the six helpers are convert in each direction`() {
        assertEquals("Oʻzbekiston", UzTranslit.cyrToLat("Ўзбекистон"))
        assertEquals("Özbekiston", UzTranslit.cyrToNew("Ўзбекистон"))
        assertEquals("Ўзбекистон", UzTranslit.latToCyr("Oʻzbekiston"))
        assertEquals("Ўзбекистон", UzTranslit.newToCyr("Özbekiston"))
        assertEquals("Toşkent şahri, Ishoq", UzTranslit.latToNew("Toshkent shahri, Is'hoq"))
        assertEquals("Toshkent shahri, Isʼhoq", UzTranslit.newToLat("Toşkent şahri, Ishoq"))
        assertEquals("O'zbekiston ma'no", UzTranslit.cyrToLat("Ўзбекистон маъно", UzTranslit.Options.ASCII))
    }

    @Test
    fun `no locale-dependent case mapping`() {
        val saved = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("tr-TR")) // "I".lowercase() would be "ı" here
            assertEquals("МИЛИЦИЯ РАЦИОН ИЛЁС", UzTranslit.convert("MILITSIYA RATSION ILYOS", "lat", "cyr"))
            assertEquals("İ ı", UzTranslit.convert("İ ı", "lat", "cyr"))
        } finally {
            Locale.setDefault(saved)
        }
    }

    @Test
    fun `surrogate pairs and empty text pass through`() {
        assertEquals("😀 шаҳар", UzTranslit.convert("😀 shahar", "lat", "cyr"))
        assertEquals("", UzTranslit.convert("", "cyr", "new"))
        assertEquals("lat", UzTranslit.detect(""))
    }

    @Test
    fun `urls, e-mail addresses and handles are left alone`() {
        assertEquals(
            "Сайт: https://latin.jaybi.uz/shahar, @shahar, ali@shahar.uz шаҳар",
            UzTranslit.convert("Sayt: https://latin.jaybi.uz/shahar, @shahar, ali@shahar.uz shahar", "lat", "cyr"),
        )
        assertEquals(
            "Сайт: ҳттпс://латин.жайби.уз/шаҳар",
            UzTranslit.convert("Sayt: https://latin.jaybi.uz/shahar", "lat", "cyr", UzTranslit.Options(skipUrls = false)),
        )
    }
}
