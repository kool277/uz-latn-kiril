package uz.jaybi.uztranslit.model

import java.nio.charset.Charset
import java.util.Locale
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class TextFilesTest {
    @Test
    fun `output names carry the target alphabet`() {
        assertEquals("hujjat-new.txt", outputFileName("hujjat.txt", Script.NEW))
        assertEquals("hujjat-cyr.md", outputFileName("hujjat.md", Script.CYR))
        assertEquals("hujjat-lat.srt", outputFileName("hujjat-cyr.srt", Script.LAT)) // a previous suffix is replaced
        assertEquals("hujjat-new.csv", outputFileName("hujjat-LAT.csv", Script.NEW))
        assertEquals("my.notes-new.txt", outputFileName("my.notes.txt", Script.NEW))
        assertEquals("notes-new.txt", outputFileName("notes", Script.NEW))
        assertEquals("uztranslit-new.txt", outputFileName(null, Script.NEW))
        assertEquals("uztranslit-cyr.txt", outputFileName("  ", Script.CYR))
        assertEquals("-new-lat.txt", outputFileName("-new.txt", Script.LAT)) // nothing left to strip
        assertEquals(".hidden-new.txt", outputFileName(".hidden", Script.NEW))
        assertEquals("b-new.txt", outputFileName("a/b.txt", Script.NEW))
    }

    @Test
    fun `only plain text files are accepted`() {
        for (name in listOf("a.txt", "a.TXT", "a.md", "a.markdown", "a.srt", "a.csv", "a.text")) {
            assertTrue(isSupportedTextFile(name, null), name)
        }
        for (name in listOf("a.html", "a.json", "a.docx", "a.xml", "a.pdf")) {
            assertFalse(isSupportedTextFile(name, "text/plain"), name)
        }
        assertTrue(isSupportedTextFile("notes", "text/plain"))
        assertTrue(isSupportedTextFile(null, "text/plain; charset=utf-8"))
        assertTrue(isSupportedTextFile(null, "application/x-subrip"))
        assertFalse(isSupportedTextFile(null, "text/html"))
        assertFalse(isSupportedTextFile(null, null))
    }

    @Test
    fun `utf-8 with and without a byte order mark`() {
        val text = "Ўзбекистон, Oʻzbekiston, Özbekiston 😀"
        assertEquals(DecodedText(text, TextEncoding.UTF8), decodeText(text.toByteArray(Charsets.UTF_8)))
        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + text.toByteArray(Charsets.UTF_8)
        assertEquals(DecodedText(text, TextEncoding.UTF8_BOM), decodeText(bom))
        assertArrayEquals(bom, encodeText(text, TextEncoding.UTF8_BOM))
        assertEquals(DecodedText("", TextEncoding.UTF8), decodeText(ByteArray(0)))
    }

    @Test
    fun `utf-16 with a byte order mark`() {
        val text = "Тошкент\r\nToshkent"
        val le = byteArrayOf(0xFF.toByte(), 0xFE.toByte()) + text.toByteArray(Charsets.UTF_16LE)
        val be = byteArrayOf(0xFE.toByte(), 0xFF.toByte()) + text.toByteArray(Charsets.UTF_16BE)
        assertEquals(DecodedText(text, TextEncoding.UTF16LE), decodeText(le))
        assertEquals(DecodedText(text, TextEncoding.UTF16BE), decodeText(be))
        assertArrayEquals(le, encodeText(text, TextEncoding.UTF16LE))
        assertArrayEquals(be, encodeText(text, TextEncoding.UTF16BE))
    }

    @Test
    fun `anything else is windows-1251 and is written back as utf-8`() {
        val text = "Тошкент шаҳри" // ҳ is not in Windows-1251: it becomes ?
        val bytes = text.toByteArray(Charset.forName("windows-1251"))
        val decoded = decodeText(bytes)
        assertEquals(TextEncoding.WINDOWS_1251, decoded.encoding)
        assertEquals("Тошкент ша?ри", decoded.text)
        assertEquals(TextEncoding.UTF8, decoded.encoding.output)
        assertEquals(TextEncoding.UTF16LE, TextEncoding.UTF16LE.output)
    }

    @Test
    fun `sizes`() {
        assertEquals("512" to SizeUnit.B, formatSize(512, Locale.ROOT))
        assertEquals("1.5" to SizeUnit.KB, formatSize(1536, Locale.ROOT))
        assertEquals("1,5" to SizeUnit.KB, formatSize(1536, Locale.forLanguageTag("ru")))
        assertEquals("150" to SizeUnit.KB, formatSize(150 * 1024, Locale.ROOT))
        assertEquals("2.0" to SizeUnit.MB, formatSize(2L * 1024 * 1024, Locale.ROOT))
    }
}
