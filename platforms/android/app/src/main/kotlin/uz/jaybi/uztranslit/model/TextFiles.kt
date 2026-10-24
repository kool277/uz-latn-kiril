package uz.jaybi.uztranslit.model

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.util.Locale

/** Shared and opened files are read whole; larger files are refused with a message. */
const val MAX_FILE_BYTES: Int = 10 * 1024 * 1024

/** The plain text formats the share target accepts (.txt .md .srt .csv): converting them as text is safe. */
val TEXT_FILE_EXTENSIONS: Set<String> = setOf("txt", "text", "md", "markdown", "srt", "csv")

/** MIME types of those files as senders label them (see the share target in AndroidManifest.xml). */
val TEXT_FILE_MIME_TYPES: List<String> = listOf(
    "text/plain", "text/markdown", "text/x-markdown", "text/csv", "text/comma-separated-values",
    "application/csv", "application/x-subrip", "text/x-subrip",
)

fun extensionOf(name: String?): String? {
    val n = name?.substringAfterLast('/') ?: return null
    val dot = n.lastIndexOf('.')
    return if (dot > 0 && dot < n.length - 1) n.substring(dot + 1).lowercase(Locale.ROOT) else null
}

/**
 * True for .txt/.md/.srt/.csv files. A name without an extension is accepted when the MIME type says plain text;
 * any other extension (.html, .json, .docx …) is refused: converting markup or keys as text would break the file.
 */
fun isSupportedTextFile(name: String?, mimeType: String?): Boolean {
    val ext = extensionOf(name)
    if (ext != null) return ext in TEXT_FILE_EXTENSIONS
    return mimeType?.lowercase(Locale.ROOT)?.substringBefore(';')?.trim() in TEXT_FILE_MIME_TYPES
}

/**
 * The name the converted file is offered under: the original name with the target's id as a suffix
 * (hujjat.txt → hujjat-new.txt). A previous -cyr/-lat/-new suffix is replaced (hujjat-cyr.txt → hujjat-lat.txt);
 * a name without an extension gets .txt.
 */
fun outputFileName(original: String?, target: Script): String {
    val name = original?.substringAfterLast('/')?.trim()?.takeIf { it.isNotEmpty() } ?: "uztranslit.txt"
    val dot = name.lastIndexOf('.')
    val base = if (dot > 0) name.substring(0, dot) else name
    val ext = if (dot > 0) name.substring(dot) else ".txt"
    val stem = Script.entries.map { "-" + it.id }.firstOrNull { base.endsWith(it, ignoreCase = true) && base.length > it.length }
        ?.let { base.dropLast(it.length) } ?: base
    return "$stem-${target.id}$ext"
}

/** How a text file was encoded; the converted file is written the same way, except legacy files become UTF-8. */
enum class TextEncoding(val charsetName: String, val bom: ByteArray) {
    UTF8("UTF-8", byteArrayOf()),
    UTF8_BOM("UTF-8", byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())),
    UTF16LE("UTF-16LE", byteArrayOf(0xFF.toByte(), 0xFE.toByte())),
    UTF16BE("UTF-16BE", byteArrayOf(0xFE.toByte(), 0xFF.toByte())),

    /** Windows Cyrillic, the usual encoding of old Uzbek Cyrillic text files that are not UTF-8. */
    WINDOWS_1251("windows-1251", byteArrayOf()),
    ;

    val charset: Charset get() = Charset.forName(charsetName)

    /** The encoding of the converted file: Windows-1251 has no ў қ ғ ҳ or ö ğ ş ç, so it becomes UTF-8. */
    val output: TextEncoding get() = if (this == WINDOWS_1251) UTF8 else this
}

data class DecodedText(val text: String, val encoding: TextEncoding)

/**
 * Decodes a text file without losing anything: a byte order mark decides (UTF-8, UTF-16LE/BE); otherwise valid
 * UTF-8 is UTF-8 and anything else is read as Windows-1251, where every byte is a character.
 */
fun decodeText(bytes: ByteArray): DecodedText {
    fun startsWith(bom: ByteArray) = bytes.size >= bom.size && bom.indices.all { bytes[it] == bom[it] }
    for (e in listOf(TextEncoding.UTF8_BOM, TextEncoding.UTF16LE, TextEncoding.UTF16BE)) {
        if (startsWith(e.bom)) {
            return DecodedText(String(bytes, e.bom.size, bytes.size - e.bom.size, e.charset), e)
        }
    }
    return try {
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        DecodedText(decoder.decode(ByteBuffer.wrap(bytes)).toString(), TextEncoding.UTF8)
    } catch (_: CharacterCodingException) {
        DecodedText(String(bytes, TextEncoding.WINDOWS_1251.charset), TextEncoding.WINDOWS_1251)
    }
}

fun encodeText(text: String, encoding: TextEncoding): ByteArray = encoding.bom + text.toByteArray(encoding.charset)

enum class SizeUnit { B, KB, MB }

/** 512 B, 12.3 KB, 4.5 MB (one decimal below 100, in the given locale). */
fun formatSize(bytes: Long, locale: Locale = Locale.getDefault()): Pair<String, SizeUnit> = when {
    bytes < 1024 -> bytes.toString() to SizeUnit.B
    bytes < 1024 * 1024 -> decimal(bytes / 1024.0, locale) to SizeUnit.KB
    else -> decimal(bytes / (1024.0 * 1024.0), locale) to SizeUnit.MB
}

private fun decimal(v: Double, locale: Locale): String =
    if (v >= 100) String.format(locale, "%.0f", v) else String.format(locale, "%.1f", v)
