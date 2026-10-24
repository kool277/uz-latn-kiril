// SPEC §5: the index-based scanners of core/js/uztranslit.js, ported one to one with the same helper names
// (cyrToLatin, latinToCyrScan, convertWordWithDict, latToNew, newToLat, detect). Text is a [UInt16] of UTF-16 code
// units; every scanner sees only the text it is given, like the reference sees the slice it is called with.

// Output pieces (lowercase; caseOut applies the casing rule).
private let A_YE: [UInt16] = [0x79, 0x65] // ye
private let A_E: [UInt16] = [0x65] // e
private let A_TS: [UInt16] = [0x74, 0x73] // ts
private let A_S: [UInt16] = [0x73] // s
private let A_SH: [UInt16] = [0x73, 0x68] // sh
private let A_CH: [UInt16] = [0x63, 0x68] // ch
private let A_S_CEDILLA: [UInt16] = [0x15F] // ş
private let A_C_CEDILLA: [UInt16] = [0xE7] // ç
private let A_O_DIAERESIS: [UInt16] = [0xF6] // ö
private let A_G_BREVE: [UInt16] = [0x11F] // ğ
private let A_EMPTY: [UInt16] = []

/// SPEC §5.1 simple table: lowercase Cyrillic → Latin, indexed by code unit - 0x400.
private let C2L: [[UInt16]] = {
    var t = [[UInt16]](repeating: [], count: 0x100)
    let src = "а a|б b|в v|г g|д d|ж j|з z|и i|й y|к k|л l|м m|н n|о o|п p|р r|т t|у u|ф f|х x|қ q|ҳ h|э e|ы i|ё yo|ю yu|я ya"
    for pair in src.split(separator: "|") {
        let kv = pair.split(separator: " ")
        t[Int(kv[0].utf16.first!) - 0x400] = Array(kv[1].utf16)
    }
    return t
}()

/// SPEC §5.2 simple table: lowercase Latin → Cyrillic (one code unit), indexed by code unit; 0 = none.
private let L2C: [UInt16] = {
    var t = [UInt16](repeating: 0, count: 0x180)
    let src = "a а|b б|d д|f ф|g г|h ҳ|i и|j ж|k к|l л|m м|n н|o о|p п|q қ|r р|s с|t т|u у|v в|x х|y й|z з|c ц|w в|" +
        "\u{F6} ў|\u{14D} ў|\u{F5} ў|\u{11F} ғ|\u{15F} ш|\u{E7} ч"
    for pair in src.split(separator: "|") {
        let kv = pair.split(separator: " ")
        t[Int(kv[0].utf16.first!)] = kv[1].utf16.first!
    }
    return t
}()

/// The scanners with the options of one conversion.
struct Engine: Sendable {
    let okina: [UInt16]
    let tutuq: [UInt16]
    let dropHardSignAfterO: Bool
    let tsFinal: Bool
    let dictionary: Bool
    private let oOkina: [UInt16] // "o" + okina
    private let gOkina: [UInt16] // "g" + okina
    private let sTutuq: [UInt16] // "s" + tutuq

    init(_ o: Options) {
        okina = Array(o.okina.utf16)
        tutuq = Array(o.tutuq.utf16)
        dropHardSignAfterO = o.dropHardSignAfterO
        tsFinal = o.tsFinal
        dictionary = o.dictionary
        oOkina = [0x6F] + okina
        gOkina = [0x67] + okina
        sTutuq = [0x73] + tutuq
    }

    // ------------------------------------------------------------ Cyrillic → Latin (SPEC §5.1)

    func cyrToLatin(_ text: [UInt16], _ target: Script) -> [UInt16] {
        let isNew = target == .new
        let n = text.count
        var out: [UInt16] = []
        out.reserveCapacity(n + n / 4)
        for i in 0..<n {
            let c = Int(text[i])
            if !isCyr(c) { out.append(text[i]); continue }
            let L = cyrLower(c), up = isCyrUpper(c)
            let P = i > 0 ? Int(text[i - 1]) : NONE
            let N = i + 1 < n ? Int(text[i + 1]) : NONE
            let r: [UInt16]
            switch L {
            case 0x435: // е
                let pl = cyrLower(P)
                r = (!isCyr(P) || isCyrVowel(P) || pl == 0x44A || pl == 0x44C) ? A_YE : A_E
            case 0x446: // ц
                r = isCyrVowel(P) ? A_TS : A_S
            case 0x44A: // ъ
                let nl = cyrLower(N)
                if nl == 0x435 || nl == 0x451 || nl == 0x44E || nl == 0x44F { r = A_EMPTY } // before е ё ю я
                else if cyrLower(P) == 0x45E && dropHardSignAfterO { r = A_EMPTY } // ўъ
                else { r = tutuq }
            case 0x44C: r = A_EMPTY // ь
            case 0x448, 0x449: r = isNew ? A_S_CEDILLA : A_SH // ш щ
            case 0x447: r = isNew ? A_C_CEDILLA : A_CH // ч
            case 0x45E: r = isNew ? A_O_DIAERESIS : oOkina // ў
            case 0x493: r = isNew ? A_G_BREVE : gOkina // ғ
            case 0x441: r = (!isNew && cyrLower(N) == 0x4B3) ? sTutuq : A_S // с, с + ҳ
            default:
                let t = C2L[L - 0x400]
                r = t.isEmpty ? [text[i]] : t
            }
            out.append(contentsOf: caseOut(text, i, up, r))
        }
        return out
    }

    // ------------------------------------------------------------ Latin → Cyrillic (SPEC §5.2)

    /// `prevCtx`: the character before `text` (the last letter of a dictionary stem), or NONE.
    func latinToCyrScan(_ text: [UInt16], _ source: Script, _ prevCtx: Int) -> [UInt16] {
        let isNew = source == .new
        let n = text.count
        var out: [UInt16] = []
        out.reserveCapacity(n)
        func prevChar(_ idx: Int) -> Int { idx > 0 ? Int(text[idx - 1]) : prevCtx }
        @inline(__always) func emit(_ up: Bool, _ upper: UInt16, _ lower: UInt16) { out.append(up ? upper : lower) }
        var i = 0
        while i < n {
            let c = Int(text[i])
            if isApos(c) {
                let pc = prevChar(i), nc = at(text, i + 1)
                if isLat(pc) && isLat(nc) { emit(isLatUpper(pc), 0x42A, 0x44A) } // maʼno → маъно
                else if isLat(pc) && c == TUTUQ_CODE { emit(isLatUpper(pc), 0x42A, 0x44A) } // word-final tutuq
                else { out.append(text[i]) } // quotes stay quotes
                i += 1; continue
            }
            if !isLat(c) { out.append(text[i]); i += 1; continue }
            let L = latLower(c), up = isLatUpper(c)
            let N = at(text, i + 1), N2 = at(text, i + 2)
            let NL = latLower(N)
            let P = prevChar(i)
            let prevIsLetter = isLat(P)
            let prevIsVowelOrApos = isLatVowel(P) || isApos(P)

            if L == 0x6F && isApos(N) { emit(up, 0x40E, 0x45E); i += 2; continue } // oʻ → ў
            if L == 0x67 && isApos(N) { emit(up, 0x492, 0x493); i += 2; continue } // gʻ → ғ
            if L == 0x73 {
                if NL == 0x68 && !isNew { emit(up, 0x428, 0x448); i += 2; continue } // sh → ш (1995)
                if isApos(N) && latLower(N2) == 0x68 { emit(up, 0x421, 0x441); i += 2; continue } // sʼh: с, then ҳ
            }
            if L == 0x63 && NL == 0x68 { emit(up, 0x427, 0x447); i += 2; continue } // ch → ч
            if L == 0x79 && (NL == 0x6F || NL == 0x75 || NL == 0x61 || NL == 0x65) { // y + o u a e
                if NL == 0x6F && isApos(N2) { emit(up, 0x419, 0x439); i += 1; continue } // yoʻl → йўл
                if NL == 0x65 {
                    if !prevIsLetter || prevIsVowelOrApos { emit(up, 0x415, 0x435) } // Yer, Aliyev
                    else { emit(up, 0x42C, 0x44C); emit(up, 0x415, 0x435) } // pyesa → пьеса
                } else if NL == 0x6F { emit(up, 0x401, 0x451) } // ё
                else if NL == 0x75 { emit(up, 0x42E, 0x44E) } // ю
                else { emit(up, 0x42F, 0x44F) } // я
                i += 2; continue
            }
            if L == 0x65 { // e: э at the start of a word or after a vowel, else е
                if !prevIsLetter || prevIsVowelOrApos { emit(up, 0x42D, 0x44D) } else { emit(up, 0x415, 0x435) }
                i += 1; continue
            }
            if L == 0x74 && NL == 0x73 { // ts
                let r0 = asciiLower(at(text, i + 2)), r1 = asciiLower(at(text, i + 3)), r2 = asciiLower(at(text, i + 4))
                if r0 == 0x69 && ((r1 == 0x79 && r2 == 0x61) || (r1 == 0x6F && r2 == 0x6E)) { // -tsiya, -tsion
                    emit(up, 0x426, 0x446); i += 2; continue
                }
                let wordEnds = i + 2 >= n || !isLat(Int(text[i + 2]))
                if tsFinal && wordEnds && isLatVowel(P) { emit(up, 0x426, 0x446); i += 2; continue } // abzats
                // otherwise т + с (oʻtsa, ketsa)
            }
            let r = L < L2C.count ? Int(L2C[L]) : 0
            if r == 0 { out.append(text[i]); i += 1; continue }
            out.append(UInt16(up ? cyrUpper(r) : r))
            i += 1
        }
        return out
    }

    func latinToCyr(_ text: [UInt16], _ source: Script) -> [UInt16] {
        if !dictionary { return latinToCyrScan(text, source, NONE) }
        let n = text.count
        var out: [UInt16] = []
        out.reserveCapacity(n)
        var i = 0
        while i < n {
            let c = Int(text[i])
            if !isLat(c) && !isApos(c) { out.append(text[i]); i += 1; continue }
            var j = i
            while j < n && (isLat(Int(text[j])) || isApos(Int(text[j]))) { j += 1 }
            out.append(contentsOf: convertWordWithDict(Array(text[i..<j]), source))
            i = j
        }
        return out
    }

    /// One word (a maximal run of Latin letters and apostrophes): dictionary stem + scanned remainder.
    func convertWordWithDict(_ word: [UInt16], _ source: Script) -> [UInt16] {
        guard let hit = DICT.lookup(normKey(word)) else { return latinToCyrScan(word, source, NONE) }
        // how many source characters does the stem cover? (normKey may expand ö → o', ş → sh …)
        var consumed = 0, built = 0
        while built < hit.key.count && consumed < word.count {
            built += normKey([word[consumed]]).count
            consumed += 1
        }
        let stemSrc = word[0..<consumed]
        let rest = Array(word[consumed...])
        // casing
        var letters = 0, uppers = 0
        var firstUpper = false
        for u in stemSrc where isLat(Int(u)) {
            letters += 1
            if isLatUpper(Int(u)) {
                uppers += 1
                if letters == 1 { firstUpper = true }
            }
        }
        let cyrStem: [UInt16]
        if letters >= 2 && uppers == letters { cyrStem = upperStr(hit.value) }
        else if firstUpper { cyrStem = upperFirst(hit.value) }
        else { cyrStem = hit.value }
        let lastSrc = stemSrc.last.map { Int($0) } ?? NONE
        return cyrStem + latinToCyrScan(rest, source, lastSrc)
    }

    // ------------------------------------------------------------ Latin 1995 → Latin 2026 (SPEC §5.3)

    func latToNew(_ text: [UInt16]) -> [UInt16] {
        let n = text.count
        var out: [UInt16] = []
        out.reserveCapacity(n)
        var i = 0
        while i < n {
            let c = Int(text[i]), L = latLower(c), up = isLatUpper(c)
            let N = at(text, i + 1), NL = latLower(N)
            let N2 = at(text, i + 2)
            if isApos(c) {
                let pc = at(text, i - 1)
                if isLat(pc) && isLat(N) { out.append(contentsOf: tutuq) } else { out.append(text[i]) }
                i += 1; continue
            }
            if !isLat(c) { out.append(text[i]); i += 1; continue }
            if L == 0x6F && isApos(N) { out.append(up ? 0xD6 : 0xF6); i += 2; continue } // oʻ → ö
            if L == 0x67 && isApos(N) { out.append(up ? 0x11E : 0x11F); i += 2; continue } // gʻ → ğ
            if L == 0x73 && NL == 0x68 { out.append(up ? 0x15E : 0x15F); i += 2; continue } // sh → ş
            if L == 0x73 && isApos(N) && latLower(N2) == 0x68 { out.append(text[i]); i += 2; continue } // sʼh → sh
            if L == 0x63 && NL == 0x68 { out.append(up ? 0xC7 : 0xE7); i += 2; continue } // ch → ç
            if L == 0x14D || L == 0xF5 { out.append(up ? 0xD6 : 0xF6); i += 1; continue } // ō õ → ö
            out.append(text[i])
            i += 1
        }
        return out
    }

    // ------------------------------------------------------------ Latin 2026 → Latin 1995 (SPEC §5.4)

    func newToLat(_ text: [UInt16]) -> [UInt16] {
        let n = text.count
        var out: [UInt16] = []
        out.reserveCapacity(n + n / 8)
        var i = 0
        while i < n {
            let c = Int(text[i]), L = latLower(c), up = isLatUpper(c)
            let N = at(text, i + 1), NL = latLower(N)
            if isApos(c) {
                let pc = at(text, i - 1)
                if isLat(pc) && isLat(N) { out.append(contentsOf: tutuq) } else { out.append(text[i]) }
                i += 1; continue
            }
            if !isLat(c) { out.append(text[i]); i += 1; continue }
            if L == 0xF6 || L == 0x14D || L == 0xF5 { out.append(up ? 0x4F : 0x6F); out.append(contentsOf: okina); i += 1; continue }
            if L == 0x11F { out.append(up ? 0x47 : 0x67); out.append(contentsOf: okina); i += 1; continue }
            if L == 0x15F { out.append(contentsOf: caseOut(text, i, up, A_SH)); i += 1; continue }
            if L == 0xE7 { out.append(contentsOf: caseOut(text, i, up, A_CH)); i += 1; continue }
            if L == 0x73 && NL == 0x68 { out.append(text[i]); out.append(contentsOf: tutuq); i += 1; continue } // Ishoq → Isʼhoq
            out.append(text[i])
            i += 1
        }
        return out
    }
}

/// normKey: a Latin word normalised for dictionary lookup — lowercase, every apostrophe → ', ö ō õ → o', ğ → g',
/// ş → sh, ç → ch.
func normKey(_ word: [UInt16]) -> [UInt16] {
    var o: [UInt16] = []
    o.reserveCapacity(word.count + 4)
    for u in word {
        let c = latLower(Int(u))
        if isApos(c) { o.append(0x27) }
        else if c == 0xF6 || c == 0x14D || c == 0xF5 { o.append(0x6F); o.append(0x27) }
        else if c == 0x11F { o.append(0x67); o.append(0x27) }
        else if c == 0x15F { o.append(0x73); o.append(0x68) }
        else if c == 0xE7 { o.append(0x63); o.append(0x68) }
        else { o.append(UInt16(c)) }
    }
    return o
}

// ---------------------------------------------------------------- detection (SPEC §5.5)

func detect(_ text: [UInt16]) -> Script {
    var cyr = 0, lat = 0, nw = 0, dig = 0
    let n = text.count
    for i in 0..<n {
        let c = Int(text[i])
        if isCyr(c) { cyr += 1; continue }
        if isLat(c) {
            lat += 1
            let L = latLower(c)
            if L == 0xF6 || L == 0x11F || L == 0x15F || L == 0xE7 || L == 0x14D || L == 0xF5 { nw += 1 } // ö ğ ş ç ō õ
            let N = at(text, i + 1), NL = latLower(N)
            if (L == 0x73 || L == 0x63) && NL == 0x68 { dig += 1 } // sh ch
            if (L == 0x6F || L == 0x67) && isApos(N) { dig += 1 } // oʻ gʻ
        }
    }
    if cyr > lat { return .cyr }
    if nw > 0 && nw >= dig { return .new }
    return .lat
}
