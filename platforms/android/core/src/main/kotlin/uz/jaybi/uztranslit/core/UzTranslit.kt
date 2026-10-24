package uz.jaybi.uztranslit.core

/**
 * UzTranslit: Uzbek script converter, Cyrillic (1940) ⇄ Latin 1995 ⇄ Latin 2026 (OʻRQ-1184: Oʻ→Ö, Gʻ→Ğ, Sh→Ş, Ch→Ç).
 *
 * A faithful Kotlin port of spec/SPEC.md v1.0.0, written function by function from the reference implementation
 * core/js/uztranslit.js: the same index-based scanners and the same SPEC §5 helper names (isCyr, isLat, isApos,
 * nextLetterIsUpper, caseOut, cyrToLatin, latinToCyrScan, convertWordWithDict, latToNew, newToLat, detect).
 *
 * Kotlin strings are UTF-16 like JavaScript strings, and every scanner walks UTF-16 code units ([Char]), never code
 * points: all letters involved are in the BMP, so a surrogate pair is simply two non-letters that are copied.
 * Case mapping only uses the letter tables below, never `String.lowercase()`/`uppercase()`, which would also map
 * letters the reference leaves alone (İ, ı, ß, the Kelvin sign …) and, in a Turkish locale, map I to ı.
 *
 * The object is immutable after initialisation and safe to use from any thread.
 */
public object UzTranslit {
    public const val VERSION: String = "1.0.0"

    /** ʻ (U+02BB), the mark in Oʻ and Gʻ (output of `lat`). */
    public const val OKINA: String = "\u02BB"

    /** ʼ (U+02BC), tutuq belgisi (output of `lat` and `new`). */
    public const val TUTUQ: String = "\u02BC"

    /** Uzbek Cyrillic (1940). */
    public const val CYR: String = "cyr"

    /** Uzbek Latin 1995 (Oʻ Gʻ Sh Ch). */
    public const val LAT: String = "lat"

    /** Uzbek Latin 2026 (Ö Ğ Ş Ç). */
    public const val NEW: String = "new"

    /** Source for [convert]: detect the script first (SPEC §5.5). */
    public const val AUTO: String = "auto"

    public val SCRIPTS: List<String> = listOf(CYR, LAT, NEW)

    /**
     * Conversion options (SPEC §2) with the reference defaults. [okina] and [tutuq] are the marks written in
     * Oʻ/Gʻ and for ъ/tutuq: one character, or empty to write none.
     */
    public data class Options(
        val okina: String = OKINA,
        val tutuq: String = TUTUQ,
        /** Cyrillic ўъ → oʻ / ö (мўъжиза → moʻjiza, möjiza). */
        val dropHardSignAfterO: Boolean = true,
        /** Latin word-final `ts` after a vowel → ц (abzats → абзац). */
        val tsFinal: Boolean = true,
        /** Apply the stem dictionary (SPEC §6, [UzDictionary]) in Latin → Cyrillic. */
        val dictionary: Boolean = true,
        /** Leave URLs, e-mail addresses and @handles unchanged (SPEC §5.6). */
        val skipUrls: Boolean = true,
    ) {
        init {
            require(okina.length <= 1) { "okina must be empty or a single character, got \"$okina\"" }
            require(tutuq.length <= 1) { "tutuq must be empty or a single character, got \"$tutuq\"" }
        }

        public companion object {
            /** The SPEC defaults. */
            public val DEFAULT: Options = Options()

            /** The defaults with the ASCII apostrophe as okina and tutuq (O'zbekiston, ma'no). */
            public val ASCII: Options = Options(okina = "'", tutuq = "'")
        }
    }

    // ------------------------------------------------------------------ public API (SPEC §2)

    /**
     * Converts [text] from one script to another. [from] is [CYR], [LAT], [NEW] or [AUTO]; [to] is [CYR], [LAT]
     * or [NEW]. When the (detected) source equals the target, [text] itself is returned unchanged.
     *
     * @throws IllegalArgumentException for an unknown direction.
     */
    public fun convert(text: String, from: String, to: String, options: Options = Options.DEFAULT): String {
        val source = if (from == AUTO) detect(text) else from
        if (source == to) return text
        val scan: (String, StringBuilder) -> Unit = when {
            source == CYR && (to == LAT || to == NEW) -> { s, out -> cyrToLatin(s, to, options, out) }
            (source == LAT || source == NEW) && to == CYR -> { s, out -> latinToCyr(s, source, options, out) }
            source == LAT && to == NEW -> { s, out -> latToNew(s, options, out) }
            source == NEW && to == LAT -> { s, out -> newToLat(s, options, out) }
            else -> throw IllegalArgumentException("UzTranslit: unknown direction $source -> $to")
        }
        val out = StringBuilder(text.length + (text.length shr 3) + 16)
        if (options.skipUrls) withSkips(text, out, scan) else scan(text, out)
        return out.toString()
    }

    public fun cyrToLat(text: String, options: Options = Options.DEFAULT): String = convert(text, CYR, LAT, options)

    public fun cyrToNew(text: String, options: Options = Options.DEFAULT): String = convert(text, CYR, NEW, options)

    public fun latToCyr(text: String, options: Options = Options.DEFAULT): String = convert(text, LAT, CYR, options)

    public fun newToCyr(text: String, options: Options = Options.DEFAULT): String = convert(text, NEW, CYR, options)

    /** Latin 1995 → Latin 2026 with URL protection; the SPEC §5.3 scanner is the internal three-argument overload. */
    public fun latToNew(text: String, options: Options = Options.DEFAULT): String = convert(text, LAT, NEW, options)

    /** Latin 2026 → Latin 1995 with URL protection; the SPEC §5.4 scanner is the internal three-argument overload. */
    public fun newToLat(text: String, options: Options = Options.DEFAULT): String = convert(text, NEW, LAT, options)

    // ------------------------------------------------------------------ character classes (SPEC §3)

    private const val CYR_LOWER = "абвгдеёжзийклмнопрстуфхцчшщъыьэюяўқғҳ"
    private const val CYR_UPPER = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎҚҒҲ"
    private const val LAT_LOWER = "abcdefghijklmnopqrstuvwxyzöğşçōõ"
    private const val LAT_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZÖĞŞÇŌÕ"
    private const val APOS = "'\u02BB\u02BC\u2018\u2019`\u00B4" // ' ʻ ʼ ‘ ’ ` ´
    private const val CYR_VOWELS = "аеёиоуэюяўы"
    private const val LAT_VOWELS = "aeiouöōõ"

    // Letters the scanners test one by one, as escapes: several Cyrillic letters look exactly like Latin ones.
    private const val CY_E = '\u0435' // е
    private const val CY_YO = '\u0451' // ё
    private const val CY_YU = '\u044E' // ю
    private const val CY_YA = '\u044F' // я
    private const val CY_YE_HARD = '\u044A' // ъ
    private const val CY_SOFT = '\u044C' // ь
    private const val CY_TS = '\u0446' // ц
    private const val CY_SH = '\u0448' // ш
    private const val CY_SHCH = '\u0449' // щ
    private const val CY_CH = '\u0447' // ч
    private const val CY_U_SHORT = '\u045E' // ў
    private const val CY_GH = '\u0493' // ғ
    private const val CY_S = '\u0441' // с
    private const val CY_H = '\u04B3' // ҳ
    private const val CY_Y = '\u0439' // й
    private const val CY_E_REV = '\u044D' // э
    private const val LA_O_UML = '\u00F6' // ö
    private const val LA_G_BREVE = '\u011F' // ğ
    private const val LA_S_CEDILLA = '\u015F' // ş
    private const val LA_C_CEDILLA = '\u00E7' // ç
    private const val LA_O_MACRON = '\u014D' // ō (2021 draft, read as ö)
    private const val LA_O_TILDE = '\u00F5' // õ (2019 draft, read as ö)
    private const val LA_O_UML_UP = '\u00D6' // Ö
    private const val LA_G_BREVE_UP = '\u011E' // Ğ
    private const val LA_S_CEDILLA_UP = '\u015E' // Ş
    private const val LA_C_CEDILLA_UP = '\u00C7' // Ç
    private const val TUTUQ_CHAR = '\u02BC' // ʼ: an explicit word-final tutuq still becomes ъ (SPEC §5.2)

    /**
     * "No character": before the start or past the end of the text (the reference's `''`). Every helper below
     * answers false for it. U+FFFF is a Unicode noncharacter that belongs to no class, so a U+FFFF inside the text
     * behaves exactly like the end of the text in every test the scanners make.
     */
    internal const val NONE: Char = '\uFFFF'

    private const val F_CYR = 1
    private const val F_CYR_UP = 2
    private const val F_LAT = 4
    private const val F_LAT_UP = 8
    private const val F_APOS = 16
    private const val F_CYR_VOWEL = 32 // set on the lowercase vowels only: isCyrVowel lowers first, like the reference
    private const val F_LAT_VOWEL = 64

    private const val CASE_N = 0x500 // every letter of the four alphabets is below U+0500
    private val FLAGS = ByteArray(0x10000)
    private val LOWER = CharArray(CASE_N) { it.toChar() }
    private val UPPER = CharArray(CASE_N) { it.toChar() }
    private val C2L = arrayOfNulls<String>(CASE_N) // lowercase Cyrillic → Latin (the plain letters of SPEC §5.1)
    private val L2C = CharArray(CASE_N) { NONE } // lowercase Latin → Cyrillic (SPEC §5.2 simple table)

    init {
        mark(CYR_LOWER, F_CYR)
        mark(CYR_UPPER, F_CYR or F_CYR_UP)
        mark(LAT_LOWER, F_LAT)
        mark(LAT_UPPER, F_LAT or F_LAT_UP)
        mark(APOS, F_APOS)
        mark(CYR_VOWELS, F_CYR_VOWEL)
        mark(LAT_VOWELS, F_LAT_VOWEL)
        for (k in CYR_LOWER.indices) {
            LOWER[CYR_UPPER[k].code] = CYR_LOWER[k]
            UPPER[CYR_LOWER[k].code] = CYR_UPPER[k]
        }
        for (k in LAT_LOWER.indices) {
            LOWER[LAT_UPPER[k].code] = LAT_LOWER[k]
            UPPER[LAT_LOWER[k].code] = LAT_UPPER[k]
        }
        val c2l = "а a|б b|в v|г g|д d|ж j|з z|и i|й y|к k|л l|м m|н n|о o|п p|р r|т t|у u|ф f|х x|қ q|ҳ h|э e|" +
            "ы i|ё yo|ю yu|я ya"
        for (pair in c2l.split('|')) C2L[pair[0].code] = pair.substring(2)
        val l2c = "a а|b б|d д|f ф|g г|h ҳ|i и|j ж|k к|l л|m м|n н|o о|p п|q қ|r р|s с|t т|u у|v в|x х|y й|z з|" +
            "c ц|w в|ö ў|ō ў|õ ў|ğ ғ|ş ш|ç ч"
        for (pair in l2c.split('|')) L2C[pair[0].code] = pair[2]
    }

    private fun mark(set: String, flag: Int) {
        for (c in set) FLAGS[c.code] = (FLAGS[c.code].toInt() or flag).toByte()
    }

    private fun flags(c: Char): Int = FLAGS[c.code].toInt()

    /** text[i], or [NONE] outside the text. */
    private fun charAt(text: String, i: Int): Char = if (i >= 0 && i < text.length) text[i] else NONE

    internal fun isCyr(c: Char): Boolean = c != NONE && (flags(c) and F_CYR) != 0

    internal fun isCyrUpper(c: Char): Boolean = c != NONE && (flags(c) and F_CYR_UP) != 0

    internal fun cyrLower(c: Char): Char = if (isCyrUpper(c)) LOWER[c.code] else c

    internal fun cyrUpper(c: Char): Char = if (isCyr(c) && !isCyrUpper(c)) UPPER[c.code] else c

    internal fun isCyrVowel(c: Char): Boolean {
        val l = cyrLower(c)
        return l != NONE && (flags(l) and F_CYR_VOWEL) != 0
    }

    internal fun isLat(c: Char): Boolean = c != NONE && (flags(c) and F_LAT) != 0

    internal fun isLatUpper(c: Char): Boolean = c != NONE && (flags(c) and F_LAT_UP) != 0

    internal fun latLower(c: Char): Char = if (isLatUpper(c)) LOWER[c.code] else c

    internal fun latUpper(c: Char): Char = if (isLat(c) && !isLatUpper(c)) UPPER[c.code] else c

    internal fun isLatVowel(c: Char): Boolean {
        val l = latLower(c)
        return l != NONE && (flags(l) and F_LAT_VOWEL) != 0
    }

    internal fun isApos(c: Char): Boolean = c != NONE && (flags(c) and F_APOS) != 0

    internal fun isLetter(c: Char): Boolean = isCyr(c) || isLat(c)

    internal fun isUpperLetter(c: Char): Boolean = isCyrUpper(c) || isLatUpper(c)

    /** ASCII-only lowering: the reference's `substr(…).toLowerCase()` can only produce "iya"/"ion" from ASCII. */
    private fun asciiLower(c: Char): Char = if (c in 'A'..'Z') c + ('a' - 'A') else c

    internal fun upperStr(s: String): String {
        val b = StringBuilder(s.length)
        for (ch in s) b.append(latUpper(cyrUpper(ch)))
        return b.toString()
    }

    internal fun upperFirst(s: String): String =
        if (s.isEmpty()) s else latUpper(cyrUpper(s[0])) + s.substring(1)

    // ------------------------------------------------------------------ casing rule (SPEC §4)

    /**
     * The next letter (skipping one apostrophe) is uppercase, or, when there is no next letter, the previous
     * letter (skipping one apostrophe) is.
     */
    internal fun nextLetterIsUpper(text: String, i: Int): Boolean {
        var j = i + 1
        if (j < text.length && isApos(text[j])) j++
        if (j < text.length && isLetter(text[j])) return isUpperLetter(text[j])
        var k = i - 1
        if (k >= 0 && isApos(text[k])) k--
        if (k >= 0 && isLetter(text[k])) return isUpperLetter(text[k])
        return false
    }

    internal fun caseOut(text: String, i: Int, srcUpper: Boolean, out: String): String {
        if (!srcUpper || out.isEmpty()) return out
        if (out.length == 1) return upperStr(out)
        return if (nextLetterIsUpper(text, i)) upperStr(out) else upperFirst(out)
    }

    // ------------------------------------------------------------------ Cyrillic → Latin (SPEC §5.1)

    internal fun cyrToLatin(text: String, target: String, o: Options, out: StringBuilder) {
        val isNew = target == NEW
        val oOkina = "o" + o.okina
        val gOkina = "g" + o.okina
        val sTutuq = "s" + o.tutuq
        val n = text.length
        for (i in 0 until n) {
            val c = text[i]
            if (!isCyr(c)) {
                out.append(c)
                continue
            }
            val l = cyrLower(c)
            val up = isCyrUpper(c)
            val p = charAt(text, i - 1)
            val nx = charAt(text, i + 1)
            val r: String = when (l) {
                CY_E -> {
                    val pl = cyrLower(p)
                    if (!isCyr(p) || isCyrVowel(p) || pl == CY_YE_HARD || pl == CY_SOFT) "ye" else "e"
                }
                CY_TS -> if (isCyrVowel(p)) "ts" else "s"
                CY_YE_HARD -> {
                    val nl = cyrLower(nx)
                    when {
                        nl == CY_E || nl == CY_YO || nl == CY_YU || nl == CY_YA -> "" // объект → obyekt
                        cyrLower(p) == CY_U_SHORT && o.dropHardSignAfterO -> "" // мўъжиза → moʻjiza
                        else -> o.tutuq
                    }
                }
                CY_SOFT -> "" // компьютер → kompyuter, альбом → albom
                CY_SH, CY_SHCH -> if (isNew) "\u015F" else "sh" // ş
                CY_CH -> if (isNew) "\u00E7" else "ch" // ç
                CY_U_SHORT -> if (isNew) "\u00F6" else oOkina // ö
                CY_GH -> if (isNew) "\u011F" else gOkina // ğ
                CY_S -> if (!isNew && cyrLower(nx) == CY_H) sTutuq else "s" // Исҳоқ → Isʼhoq; new: Ishoq
                else -> C2L[l.code] ?: c.toString()
            }
            out.append(caseOut(text, i, up, r))
        }
    }

    // ------------------------------------------------------------------ Latin → Cyrillic (SPEC §5.2)

    private fun StringBuilder.cyr(lower: Char, up: Boolean): StringBuilder = append(if (up) cyrUpper(lower) else lower)

    /** The scanner. [prevCtx] is the letter before the text (the last letter of a dictionary stem) or [NONE]. */
    internal fun latinToCyrScan(text: String, source: String, o: Options, prevCtx: Char, out: StringBuilder) {
        val isNew = source == NEW
        val n = text.length
        var i = 0
        while (i < n) {
            val c = text[i]
            if (isApos(c)) {
                val pc = if (i > 0) text[i - 1] else prevCtx
                val nc = charAt(text, i + 1)
                if (isLat(pc) && isLat(nc)) out.cyr(CY_YE_HARD, isLatUpper(pc)) // maʼno → маъно
                else if (isLat(pc) && c == TUTUQ_CHAR) out.cyr(CY_YE_HARD, isLatUpper(pc)) // explicit word-final tutuq
                else out.append(c) // quotes stay quotes
                i++
                continue
            }
            if (!isLat(c)) {
                out.append(c)
                i++
                continue
            }
            val l = latLower(c)
            val up = isLatUpper(c)
            val nx = charAt(text, i + 1)
            val nx2 = charAt(text, i + 2)
            val nl = latLower(nx)
            val p = if (i > 0) text[i - 1] else prevCtx
            val prevIsLetter = isLat(p)
            val prevIsVowelOrApos = isLatVowel(p) || isApos(p)

            if (l == 'o' && isApos(nx)) {
                out.cyr(CY_U_SHORT, up)
                i += 2
                continue
            }
            if (l == 'g' && isApos(nx)) {
                out.cyr(CY_GH, up)
                i += 2
                continue
            }
            if (l == 's') {
                if (nl == 'h' && !isNew) { // 1995: sh = ш
                    out.cyr(CY_SH, up)
                    i += 2
                    continue
                }
                if (isApos(nx) && latLower(nx2) == 'h') { // Isʼhoq: drop the separator, h → ҳ next
                    out.cyr(CY_S, up)
                    i += 2
                    continue
                }
            }
            if (l == 'c' && nl == 'h') { // tolerated in both sources
                out.cyr(CY_CH, up)
                i += 2
                continue
            }
            if (l == 'y' && (nl == 'o' || nl == 'u' || nl == 'a' || nl == 'e')) {
                if (nl == 'o' && isApos(nx2)) { // yoʻl → йўл
                    out.cyr(CY_Y, up)
                    i += 1
                    continue
                }
                when (nl) {
                    'e' -> if (!prevIsLetter || prevIsVowelOrApos) {
                        out.cyr(CY_E, up) // Yer, Aliyev, Xoʻjayev
                    } else {
                        out.cyr(CY_SOFT, up).cyr(CY_E, up) // pyesa → пьеса
                    }
                    'o' -> out.cyr(CY_YO, up)
                    'u' -> out.cyr(CY_YU, up)
                    else -> out.cyr(CY_YA, up)
                }
                i += 2
                continue
            }
            if (l == 'e') { // Ekologiya, poema / Toshkent
                out.cyr(if (!prevIsLetter || prevIsVowelOrApos) CY_E_REV else CY_E, up)
                i++
                continue
            }
            if (l == 't' && nl == 's') {
                // reference: text.substr(i + 2, 3).toLowerCase() starts with "iya" or "ion"
                val r0 = asciiLower(charAt(text, i + 2))
                val r1 = asciiLower(charAt(text, i + 3))
                val r2 = asciiLower(charAt(text, i + 4))
                if (r0 == 'i' && ((r1 == 'y' && r2 == 'a') || (r1 == 'o' && r2 == 'n'))) { // militsiya, ratsion
                    out.cyr(CY_TS, up)
                    i += 2
                    continue
                }
                val wordEnds = i + 2 >= n || !isLat(text[i + 2])
                if (o.tsFinal && wordEnds && isLatVowel(p)) { // abzats; native oʻtsa, ketsa keep т+с
                    out.cyr(CY_TS, up)
                    i += 2
                    continue
                }
            }
            val r = L2C[l.code]
            if (r == NONE) {
                out.append(c)
                i++
                continue
            }
            out.cyr(r, up)
            i++
        }
    }

    /** Word pre-pass: every maximal run of Latin letters and apostrophes goes through the dictionary. */
    internal fun latinToCyr(text: String, source: String, o: Options, out: StringBuilder) {
        if (!o.dictionary) {
            latinToCyrScan(text, source, o, NONE, out)
            return
        }
        val n = text.length
        var i = 0
        while (i < n) {
            val c = text[i]
            if (!isLat(c) && !isApos(c)) {
                out.append(c)
                i++
                continue
            }
            var j = i
            while (j < n && (isLat(text[j]) || isApos(text[j]))) j++
            convertWordWithDict(text.substring(i, j), source, o, out)
            i = j
        }
    }

    /** Dictionary lookup key: lowercase, every apostrophe → ', ö/ō/õ → o', ğ → g', ş → sh, ç → ch. */
    internal fun normKey(word: String): String {
        val b = StringBuilder(word.length + 4)
        for (ch in word) {
            val c = latLower(ch)
            when {
                isApos(c) -> b.append('\'')
                c == LA_O_UML || c == LA_O_MACRON || c == LA_O_TILDE -> b.append("o'")
                c == LA_G_BREVE -> b.append("g'")
                c == LA_S_CEDILLA -> b.append("sh")
                c == LA_C_CEDILLA -> b.append("ch")
                else -> b.append(c)
            }
        }
        return b.toString()
    }

    /** Length of normKey(c) for one character. */
    private fun normLen(ch: Char): Int {
        val c = latLower(ch)
        return if (c == LA_O_UML || c == LA_O_MACRON || c == LA_O_TILDE || c == LA_G_BREVE ||
            c == LA_S_CEDILLA || c == LA_C_CEDILLA
        ) 2 else 1
    }

    internal fun convertWordWithDict(word: String, source: String, o: Options, out: StringBuilder) {
        val hit = UzDictionary.longestPrefixOf(normKey(word))
        if (hit == null) {
            latinToCyrScan(word, source, o, NONE, out)
            return
        }
        // how many source characters does the stem cover? (normKey may expand ö → o', ş → sh …)
        var consumed = 0
        var built = 0
        while (built < hit.length && consumed < word.length) {
            built += normLen(word[consumed])
            consumed++
        }
        var letters = 0
        var uppers = 0
        var firstUpper = false
        for (q in 0 until consumed) {
            val ch = word[q]
            if (isLat(ch)) {
                letters++
                if (isLatUpper(ch)) {
                    uppers++
                    if (letters == 1) firstUpper = true
                }
            }
        }
        val value = UzDictionary[hit]!!
        out.append(
            when {
                letters >= 2 && uppers == letters -> upperStr(value)
                firstUpper -> upperFirst(value)
                else -> value
            },
        )
        latinToCyrScan(word.substring(consumed), source, o, word[consumed - 1], out)
    }

    // ------------------------------------------------------------------ Latin 1995 → Latin 2026 (SPEC §5.3)

    internal fun latToNew(text: String, o: Options, out: StringBuilder) {
        val n = text.length
        var i = 0
        while (i < n) {
            val c = text[i]
            val l = latLower(c)
            val up = isLatUpper(c)
            val nx = charAt(text, i + 1)
            val nl = latLower(nx)
            val nx2 = charAt(text, i + 2)
            if (isApos(c)) {
                val pc = charAt(text, i - 1)
                if (isLat(pc) && isLat(nx)) out.append(o.tutuq) else out.append(c)
                i++
                continue
            }
            if (!isLat(c)) {
                out.append(c)
                i++
                continue
            }
            if (l == 'o' && isApos(nx)) {
                out.append(if (up) LA_O_UML_UP else LA_O_UML)
                i += 2
                continue
            }
            if (l == 'g' && isApos(nx)) {
                out.append(if (up) LA_G_BREVE_UP else LA_G_BREVE)
                i += 2
                continue
            }
            if (l == 's' && nl == 'h') {
                out.append(if (up) LA_S_CEDILLA_UP else LA_S_CEDILLA)
                i += 2
                continue
            }
            if (l == 's' && isApos(nx) && latLower(nx2) == 'h') { // Isʼhoq → Ishoq
                out.append(c)
                i += 2
                continue
            }
            if (l == 'c' && nl == 'h') {
                out.append(if (up) LA_C_CEDILLA_UP else LA_C_CEDILLA)
                i += 2
                continue
            }
            if (l == LA_O_MACRON || l == LA_O_TILDE) { // legacy drafts
                out.append(if (up) LA_O_UML_UP else LA_O_UML)
                i++
                continue
            }
            out.append(c)
            i++
        }
    }

    // ------------------------------------------------------------------ Latin 2026 → Latin 1995 (SPEC §5.4)

    internal fun newToLat(text: String, o: Options, out: StringBuilder) {
        val n = text.length
        var i = 0
        while (i < n) {
            val c = text[i]
            val l = latLower(c)
            val up = isLatUpper(c)
            val nx = charAt(text, i + 1)
            val nl = latLower(nx)
            if (isApos(c)) {
                val pc = charAt(text, i - 1)
                if (isLat(pc) && isLat(nx)) out.append(o.tutuq) else out.append(c)
                i++
                continue
            }
            if (!isLat(c)) {
                out.append(c)
                i++
                continue
            }
            if (l == LA_O_UML || l == LA_O_MACRON || l == LA_O_TILDE) {
                out.append(if (up) 'O' else 'o').append(o.okina)
                i++
                continue
            }
            if (l == LA_G_BREVE) {
                out.append(if (up) 'G' else 'g').append(o.okina)
                i++
                continue
            }
            if (l == LA_S_CEDILLA) { // ŞAHAR → SHAHAR, Şahar → Shahar, Ş → Sh
                out.append(caseOut(text, i, up, "sh"))
                i++
                continue
            }
            if (l == LA_C_CEDILLA) {
                out.append(caseOut(text, i, up, "ch"))
                i++
                continue
            }
            if (l == 's' && nl == 'h') { // Ishoq → Isʼhoq
                out.append(c).append(o.tutuq)
                i++
                continue
            }
            out.append(c)
            i++
        }
    }

    // ------------------------------------------------------------------ detection (SPEC §5.5)

    /** The script of [text]: [CYR], [NEW] or [LAT] (also for empty or letterless text). */
    public fun detect(text: String): String {
        var cyr = 0
        var lat = 0
        var nw = 0
        var dig = 0
        val n = text.length
        for (i in 0 until n) {
            val c = text[i]
            if (isCyr(c)) {
                cyr++
                continue
            }
            if (isLat(c)) {
                lat++
                val l = latLower(c)
                if (l == LA_O_UML || l == LA_G_BREVE || l == LA_S_CEDILLA || l == LA_C_CEDILLA ||
                    l == LA_O_MACRON || l == LA_O_TILDE
                ) {
                    nw++
                }
                val nx = charAt(text, i + 1)
                val nl = latLower(nx)
                if ((l == 's' || l == 'c') && nl == 'h') dig++
                if ((l == 'o' || l == 'g') && isApos(nx)) dig++
            }
        }
        if (cyr > lat) return CYR
        if (nw > 0 && nw >= dig) return NEW
        return LAT
    }

    // ------------------------------------------------------------------ URL / e-mail protection (SPEC §5.6)

    /** JavaScript RegExp `\s`: [\t\n\v\f\r \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]. */
    private fun isJsSpace(c: Char): Boolean = when (c.code) {
        in 0x09..0x0D, 0x20, 0xA0, 0x1680, in 0x2000..0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF -> true
        else -> false
    }

    /** JavaScript RegExp `\w` without the u flag: ASCII [A-Za-z0-9_] only. */
    private fun isJsWordChar(c: Char): Boolean = c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c == '_'

    /** Length of the `https?://` or `www.` prefix at [p] (case-sensitive, like the reference), or 0. */
    private fun urlPrefix(text: String, p: Int): Int {
        val n = text.length
        if (text.startsWith("www.", p)) return 4
        if (p + 7 <= n && text.startsWith("http", p)) {
            var q = p + 4
            if (text[q] == 's') q++
            if (text.startsWith("://", q)) return q + 3 - p
        }
        return 0
    }

    /**
     * Copies the tokens of the reference expression `/(https?:\/\/|www\.)\S+|\S+@\S+\.\S+|@\w+/g` unchanged and
     * converts the text between them, slice by slice, exactly like the reference (each slice is a text of its own).
     * The expression is evaluated by scanning, with JavaScript's `\s` and `\w`: at a position p,
     *  - `(https?:\/\/|www\.)\S+` matches when a prefix starts at p and a non-space follows it, up to the run end;
     *  - `\S+@\S+\.\S+` matches from p to the end of the run of non-spaces iff some '@' at x >= p+1 is followed by
     *    a '.' at y >= x+2 with y <= runEnd-2; the last such '.' and the last '@' before it decide that;
     *  - `@\w+` matches an '@' followed by at least one word character, greedily.
     */
    private inline fun withSkips(text: String, out: StringBuilder, fn: (String, StringBuilder) -> Unit) {
        val n = text.length
        var last = 0
        var p = 0
        var runEnd = -1
        var runAt = -1
        while (p < n) {
            val c = text[p]
            if (isJsSpace(c)) {
                p++
                continue
            }
            if (p >= runEnd) { // a new run of non-spaces starts at p
                runEnd = p
                while (runEnd < n && !isJsSpace(text[runEnd])) runEnd++
                var dot = -1
                for (k in runEnd - 2 downTo p) if (text[k] == '.') {
                    dot = k
                    break
                }
                runAt = -1
                for (k in dot - 2 downTo p) if (text[k] == '@') {
                    runAt = k
                    break
                }
            }
            var mEnd = -1
            val pre = urlPrefix(text, p)
            if (pre > 0 && p + pre < runEnd) {
                mEnd = runEnd
            } else if (runAt >= p + 1) {
                mEnd = runEnd
            } else if (c == '@' && p + 1 < n && isJsWordChar(text[p + 1])) {
                mEnd = p + 2
                while (mEnd < n && isJsWordChar(text[mEnd])) mEnd++
            }
            if (mEnd < 0) {
                p++
                continue
            }
            fn(text.substring(last, p), out)
            out.append(text, p, mEnd)
            last = mEnd
            p = mEnd
        }
        fn(text.substring(last), out)
    }
}
