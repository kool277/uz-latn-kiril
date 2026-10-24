package uz.jaybi.uztranslit.model

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import uz.jaybi.uztranslit.core.UzTranslit

class ModelTest {
    @Test
    fun `an explicit source is taken as chosen`() {
        assertEquals(Direction(Script.LAT, Script.CYR), resolveDirection("Тошкент", Source.LAT, Script.CYR))
        assertEquals(Direction(Script.NEW, Script.NEW), resolveDirection("Toşkent", Source.NEW, Script.NEW))
    }

    @Test
    fun `auto detects the source`() {
        assertEquals(Direction(Script.CYR, Script.NEW, Script.CYR), resolveDirection("Тошкент шаҳри", Source.AUTO, Script.NEW))
        assertEquals(Direction(Script.LAT, Script.NEW, Script.LAT), resolveDirection("Toshkent shahri", Source.AUTO, Script.NEW))
    }

    @Test
    fun `auto goes to the other alphabet family when the text is already in the target`() {
        assertEquals(Direction(Script.NEW, Script.CYR, Script.NEW), resolveDirection("Özbekiston", Source.AUTO, Script.NEW))
        assertEquals(Direction(Script.LAT, Script.CYR, Script.LAT), resolveDirection("Oʻzbekiston", Source.AUTO, Script.LAT))
        assertEquals(Direction(Script.CYR, Script.NEW, Script.CYR), resolveDirection("Ўзбекистон", Source.AUTO, Script.CYR))
        assertEquals(Direction(Script.LAT, Script.CYR, Script.LAT), resolveDirection("", Source.AUTO, Script.LAT))
    }

    @Test
    fun `settings map to engine options`() {
        assertEquals(UzTranslit.Options.DEFAULT, UserSettings().options())
        assertEquals(UzTranslit.Options.ASCII, UserSettings(asciiApostrophe = true).options())
        val o = UserSettings(dictionary = false, dropHardSignAfterO = false).options()
        assertEquals(false, o.dictionary)
        assertEquals(false, o.dropHardSignAfterO)
        assertEquals(true, o.tsFinal)
        assertEquals(true, o.skipUrls)
    }

    @Test
    fun `convertText uses the direction and the options`() {
        val d = Direction(Script.CYR, Script.LAT)
        assertEquals("Oʻzbekiston maʼno", convertText("Ўзбекистон маъно", d, UserSettings().options()))
        assertEquals("O'zbekiston ma'no", convertText("Ўзбекистон маъно", d, UserSettings(asciiApostrophe = true).options()))
    }

    @Test
    fun `stats count code points and runs of non-space`() {
        assertEquals(TextStats(0, 0), textStats(""))
        assertEquals(TextStats(15, 2), textStats("Toshkent shahri"))
        assertEquals(TextStats(4, 2), textStats("a😀 b")) // an emoji is one character
        assertEquals(TextStats(9, 3), textStats(" a\u00a0b\u2028c\t\n "))
        assertEquals(TextStats(3, 1), textStats("a\u200bb")) // a zero-width space is not a space in JavaScript
    }

    @Test
    fun `clipboard conversion`() {
        val s = UserSettings(target = Script.NEW)
        assertEquals(ClipboardResult.Empty, convertClipboard(null, s))
        assertEquals(ClipboardResult.Empty, convertClipboard("", s))
        assertEquals(ClipboardResult.Converted("Toşkent", Script.CYR, Script.NEW), convertClipboard("Тошкент", s))
        assertEquals(ClipboardResult.Converted("Toşkent", Script.LAT, Script.NEW), convertClipboard("Toshkent", s))
        assertEquals(ClipboardResult.AlreadyInTarget(Script.NEW), convertClipboard("Toşkent", s))
        assertEquals(ClipboardResult.AlreadyInTarget(Script.NEW), convertClipboard("12345", s))
        assertEquals(
            ClipboardResult.Converted("Тошкент", Script.LAT, Script.CYR),
            convertClipboard("Toshkent", UserSettings(target = Script.CYR)),
        )
    }

    @Test
    fun `ids round-trip`() {
        for (s in Script.entries) assertEquals(s, Script.of(s.id))
        for (s in Source.entries) assertEquals(s, Source.of(s.id))
        for (s in Script.entries) assertEquals(s, Source.of(s).script)
        assertEquals(null, Script.of("auto"))
    }
}
