package uz.jaybi.uztranslit.model

import uz.jaybi.uztranslit.core.UzTranslit

/** The three alphabets (SPEC §1) with the engine's ids. */
enum class Script(val id: String) {
    CYR(UzTranslit.CYR),
    LAT(UzTranslit.LAT),
    NEW(UzTranslit.NEW),
    ;

    companion object {
        fun of(id: String?): Script? = entries.firstOrNull { it.id == id }
    }
}

/** The source choice of the main screen: auto-detection or one alphabet. */
enum class Source(val id: String, val script: Script?) {
    AUTO(UzTranslit.AUTO, null),
    CYR(UzTranslit.CYR, Script.CYR),
    LAT(UzTranslit.LAT, Script.LAT),
    NEW(UzTranslit.NEW, Script.NEW),
    ;

    companion object {
        fun of(script: Script): Source = entries.first { it.script == script }

        fun of(id: String?): Source? = entries.firstOrNull { it.id == id }
    }
}

/** What the user chose; persisted (data/SettingsRepository.kt). */
data class UserSettings(
    val source: Source = Source.AUTO,
    /** The target alphabet of the main screen, the clipboard tile, selected text and shared files. */
    val target: Script = Script.NEW,
    val asciiApostrophe: Boolean = false,
    val dictionary: Boolean = true,
    val dropHardSignAfterO: Boolean = true,
) {
    /** Engine options: the SPEC defaults with the user's apostrophe style, dictionary and ўъ choices. */
    fun options(): UzTranslit.Options = UzTranslit.Options(
        okina = if (asciiApostrophe) "'" else UzTranslit.OKINA,
        tutuq = if (asciiApostrophe) "'" else UzTranslit.TUTUQ,
        dictionary = dictionary,
        dropHardSignAfterO = dropHardSignAfterO,
    )
}

/** A resolved direction; [detected] is set when the source was detected automatically. */
data class Direction(val from: Script, val to: Script, val detected: Script? = null)

/**
 * The direction for [text]. An explicit source is taken as chosen. With [Source.AUTO] the source is detected
 * (SPEC §5.5); when the text is already in [target], it goes to the other alphabet family instead (Cyrillic →
 * Latin 2026, Latin → Cyrillic), like the web app, so that "Auto" always converts.
 */
fun resolveDirection(text: String, source: Source, target: Script): Direction {
    source.script?.let { return Direction(it, target) }
    val detected = Script.of(UzTranslit.detect(text)) ?: Script.LAT
    val to = when {
        detected != target -> target
        detected == Script.CYR -> Script.NEW
        else -> Script.CYR
    }
    return Direction(detected, to, detected)
}

fun convertText(text: String, direction: Direction, options: UzTranslit.Options): String =
    UzTranslit.convert(text, direction.from.id, direction.to.id, options)

/** Characters (Unicode code points) and words (runs of non-space characters, counted like the web app). */
data class TextStats(val chars: Int, val words: Int) {
    companion object {
        val EMPTY = TextStats(0, 0)
    }
}

fun textStats(text: String): TextStats {
    var words = 0
    var inWord = false
    for (c in text) {
        val space = isSpace(c)
        if (!space && !inWord) words++
        inWord = !space
    }
    return TextStats(text.codePointCount(0, text.length), words)
}

private fun isSpace(c: Char): Boolean {
    val k = c.code
    return k <= 0x20 || k == 0xA0 || k == 0x1680 || k in 0x2000..0x200A || k == 0x2028 || k == 0x2029 ||
        k == 0x202F || k == 0x205F || k == 0x3000 || k == 0xFEFF
}

/** The clipboard tile: what converting [text] to the user's target gives. */
sealed interface ClipboardResult {
    data object Empty : ClipboardResult

    data class AlreadyInTarget(val script: Script) : ClipboardResult

    data class Converted(val text: String, val from: Script, val to: Script) : ClipboardResult
}

fun convertClipboard(text: String?, settings: UserSettings): ClipboardResult {
    if (text.isNullOrEmpty()) return ClipboardResult.Empty
    val from = Script.of(UzTranslit.detect(text)) ?: Script.LAT
    if (from == settings.target) return ClipboardResult.AlreadyInTarget(from)
    val converted = UzTranslit.convert(text, from.id, settings.target.id, settings.options())
    if (converted == text) return ClipboardResult.AlreadyInTarget(settings.target) // digits, punctuation …
    return ClipboardResult.Converted(converted, from, settings.target)
}
