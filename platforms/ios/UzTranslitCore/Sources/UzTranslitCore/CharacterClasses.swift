// SPEC §3 (character classes) and §4 (casing) on UTF-16 code units, as in core/js/uztranslit.js.
//
// The engine never looks at Swift `Character`s: a Character is a grapheme cluster, so a combining mark or an emoji
// next to a letter would change what "the next character" is. Every rule of the spec is about single UTF-16 code
// units (all relevant letters are in the BMP), exactly like JavaScript strings.
//
// A character is an `Int` holding one code unit, or `NONE` for "no character" (before the start or after the end of
// the text, an empty option string): the reference's `''`. NONE is in no class and maps to itself, so every helper
// handles "no character" explicitly (in JavaScript `"".indexOf("")` is 0, which is why the reference guards it).

/// "No character".
let NONE = -1

let OKINA_CODE = 0x02BB // ʻ okina, the mark in Oʻ Gʻ
let TUTUQ_CODE = 0x02BC // ʼ tutuq belgisi

let CYR_LOWER = "абвгдеёжзийклмнопрстуфхцчшщъыьэюяўқғҳ"
let CYR_UPPER = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎҚҒҲ"
let LAT_LOWER = "abcdefghijklmnopqrstuvwxyz\u{F6}\u{11F}\u{15F}\u{E7}\u{14D}\u{F5}" // … ö ğ ş ç ō õ
let LAT_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\u{D6}\u{11E}\u{15E}\u{C7}\u{14C}\u{D5}" // … Ö Ğ Ş Ç Ō Õ
let APOS = "'\u{2BB}\u{2BC}\u{2018}\u{2019}`\u{B4}" // ' ʻ ʼ ‘ ’ ` ´
let CYR_VOWELS = "аеёиоуэюяўы"
let LAT_VOWELS = "aeiou\u{F6}\u{14D}\u{F5}" // a e i o u ö ō õ

let F_CYR: UInt8 = 1
let F_CYR_UP: UInt8 = 2
let F_LAT: UInt8 = 4
let F_LAT_UP: UInt8 = 8
let F_APOS: UInt8 = 16
let F_CYR_VOWEL: UInt8 = 32
let F_LAT_VOWEL: UInt8 = 64
let F_SPACE: UInt8 = 128 // JavaScript RegExp \s, for the URL/e-mail tokeniser (SPEC §5.6)

/// Every letter of the four alphabets is below U+0500.
let CASE_N = 0x500

/// Lookup tables built once from the strings above.
struct CharTables: Sendable {
    let flags: [UInt8] // per code unit
    let lower: [UInt16] // per code unit below CASE_N; identity except for the uppercase letters
    let upper: [UInt16] // identity except for the lowercase letters

    init() {
        var flags = [UInt8](repeating: 0, count: 0x10000)
        func mark(_ set: String, _ flag: UInt8) {
            for u in set.utf16 { flags[Int(u)] |= flag }
        }
        mark(CYR_LOWER, F_CYR)
        mark(CYR_UPPER, F_CYR | F_CYR_UP)
        mark(LAT_LOWER, F_LAT)
        mark(LAT_UPPER, F_LAT | F_LAT_UP)
        mark(APOS, F_APOS)
        var lower = (0..<CASE_N).map { UInt16($0) }
        var upper = lower
        for (lo, up) in zip(CYR_LOWER.utf16, CYR_UPPER.utf16) {
            lower[Int(up)] = lo
            upper[Int(lo)] = up
        }
        for (lo, up) in zip(LAT_LOWER.utf16, LAT_UPPER.utf16) {
            lower[Int(up)] = lo
            upper[Int(lo)] = up
        }
        // vowel classes hold both cases: isCyrVowel(c) is CYR_VOWELS.has(cyrLower(c)) in the reference
        for v in CYR_VOWELS.utf16 {
            flags[Int(v)] |= F_CYR_VOWEL
            flags[Int(upper[Int(v)])] |= F_CYR_VOWEL
        }
        for v in LAT_VOWELS.utf16 {
            flags[Int(v)] |= F_LAT_VOWEL
            flags[Int(upper[Int(v)])] |= F_LAT_VOWEL
        }
        // RegExp \s: \t \n \v \f \r, space, U+00A0, U+1680, U+2000...U+200A, U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF
        for c in 0x09...0x0D { flags[c] |= F_SPACE }
        for c in 0x2000...0x200A { flags[c] |= F_SPACE }
        for c in [0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF] { flags[c] |= F_SPACE }
        self.flags = flags
        self.lower = lower
        self.upper = upper
    }
}

let TABLES = CharTables()

@inline(__always) func fl(_ c: Int) -> UInt8 { c >= 0 ? TABLES.flags[c] : 0 }

func isCyr(_ c: Int) -> Bool { (fl(c) & F_CYR) != 0 }
func isCyrUpper(_ c: Int) -> Bool { (fl(c) & F_CYR_UP) != 0 }
func cyrLower(_ c: Int) -> Int { isCyrUpper(c) ? Int(TABLES.lower[c]) : c }
func cyrUpper(_ c: Int) -> Int { (fl(c) & (F_CYR | F_CYR_UP)) == F_CYR ? Int(TABLES.upper[c]) : c }
func isCyrVowel(_ c: Int) -> Bool { (fl(c) & F_CYR_VOWEL) != 0 }

func isLat(_ c: Int) -> Bool { (fl(c) & F_LAT) != 0 }
func isLatUpper(_ c: Int) -> Bool { (fl(c) & F_LAT_UP) != 0 }
func latLower(_ c: Int) -> Int { isLatUpper(c) ? Int(TABLES.lower[c]) : c }
func latUpper(_ c: Int) -> Int { (fl(c) & (F_LAT | F_LAT_UP)) == F_LAT ? Int(TABLES.upper[c]) : c }
func isLatVowel(_ c: Int) -> Bool { (fl(c) & F_LAT_VOWEL) != 0 }

func isApos(_ c: Int) -> Bool { (fl(c) & F_APOS) != 0 }
func isLetter(_ c: Int) -> Bool { (fl(c) & (F_CYR | F_LAT)) != 0 }
func isUpperLetter(_ c: Int) -> Bool { (fl(c) & (F_CYR_UP | F_LAT_UP)) != 0 }
func isSpace(_ c: Int) -> Bool { (fl(c) & F_SPACE) != 0 }

/// RegExp \w (without the u and i flags): ASCII letters, digits and the underscore.
func isWordChar(_ c: Int) -> Bool {
    (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
}

/// `toLowerCase()` as the reference's "iya"/"ion" test sees it: only ASCII letters can lower to i, y, a, o, n
/// (U+0130 lowers to "i" + U+0307, which never matches), so ASCII lowering is exact there.
func asciiLower(_ c: Int) -> Int { c >= 0x41 && c <= 0x5A ? c + 0x20 : c }

func upperChar(_ c: Int) -> Int { latUpper(cyrUpper(c)) }

func upperStr(_ s: [UInt16]) -> [UInt16] { s.map { UInt16(upperChar(Int($0))) } }

func upperFirst(_ s: [UInt16]) -> [UInt16] {
    guard let first = s.first else { return s }
    var out = s
    out[0] = UInt16(upperChar(Int(first)))
    return out
}

/// The code unit at `i`, or NONE outside the text.
@inline(__always) func at(_ text: [UInt16], _ i: Int) -> Int { i >= 0 && i < text.count ? Int(text[i]) : NONE }

// ---------------------------------------------------------------- casing rule (SPEC §4)

/// The next letter (skipping one apostrophe) is uppercase; with no next letter, the previous one is.
func nextLetterIsUpper(_ text: [UInt16], _ i: Int) -> Bool {
    var j = i + 1
    if j < text.count && isApos(Int(text[j])) { j += 1 }
    if j < text.count && isLetter(Int(text[j])) { return isUpperLetter(Int(text[j])) }
    var k = i - 1
    if k >= 0 && isApos(Int(text[k])) { k -= 1 }
    if k >= 0 && isLetter(Int(text[k])) { return isUpperLetter(Int(text[k])) }
    return false
}

/// Casing of the output `out` for the source letter at `i` (SPEC §4): Ш → Sh, ШАҲАР → SHAHAR.
func caseOut(_ text: [UInt16], _ i: Int, _ srcUpper: Bool, _ out: [UInt16]) -> [UInt16] {
    if !srcUpper || out.isEmpty { return out }
    if out.count == 1 { return upperStr(out) }
    return nextLetterIsUpper(text, i) ? upperStr(out) : upperFirst(out)
}
