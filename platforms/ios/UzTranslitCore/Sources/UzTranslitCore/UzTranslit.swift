// UzTranslit — Uzbek script converter: Cyrillic (1940) ⇄ Latin 1995 ⇄ Latin 2026 (OʻRQ-1184: Oʻ → Ö, Gʻ → Ğ,
// Sh → Ş, Ch → Ç). Swift port of spec/SPEC.md v1.0.0; core/js/uztranslit.js is the reference. Pure Swift.

/// A script: `cyr` Uzbek Cyrillic, `lat` Latin 1995, `new` Latin 2026.
public enum Script: String, CaseIterable, Sendable, Hashable {
    case cyr
    case lat
    case new
}

/// The source of a conversion: a script, or `auto` (detected with ``UzTranslit/detect(_:)``).
public enum SourceScript: String, CaseIterable, Sendable, Hashable {
    case auto
    case cyr
    case lat
    case new

    public init(_ script: Script) {
        switch script {
        case .cyr: self = .cyr
        case .lat: self = .lat
        case .new: self = .new
        }
    }

    /// The script, or nil for `auto`.
    public var script: Script? {
        switch self {
        case .auto: return nil
        case .cyr: return .cyr
        case .lat: return .lat
        case .new: return .new
        }
    }
}

/// Conversion options (SPEC §2). The defaults are the spec's.
public struct Options: Sendable, Hashable {
    /// Mark written in Oʻ Gʻ (Latin 1995 output): U+02BB by default, `"'"` for ASCII; may be empty.
    public var okina: String
    /// Mark written for ъ / the tutuq belgisi: U+02BC by default, `"'"` for ASCII; may be empty.
    public var tutuq: String
    /// Cyrillic ўъ → oʻ / ö (мўъжиза → moʻjiza).
    public var dropHardSignAfterO: Bool
    /// Latin word-final `ts` after a vowel → ц (abzats → абзац).
    public var tsFinal: Bool
    /// Apply the stem dictionary (SPEC §6) in Latin → Cyrillic.
    public var dictionary: Bool
    /// Leave URLs, e-mail addresses and @handles unchanged.
    public var skipUrls: Bool

    public init(
        okina: String = UzTranslit.okina,
        tutuq: String = UzTranslit.tutuq,
        dropHardSignAfterO: Bool = true,
        tsFinal: Bool = true,
        dictionary: Bool = true,
        skipUrls: Bool = true
    ) {
        self.okina = okina
        self.tutuq = tutuq
        self.dropHardSignAfterO = dropHardSignAfterO
        self.tsFinal = tsFinal
        self.dictionary = dictionary
        self.skipUrls = skipUrls
    }

    /// The spec defaults.
    public static let `default` = Options()
    /// The defaults with the ASCII apostrophe for both marks.
    public static let asciiApostrophe = Options(okina: "'", tutuq: "'")
}

/// The public API of SPEC §2.
public enum UzTranslit {
    public static let version = "1.1.0"
    /// ʻ U+02BB, the okina of Oʻ Gʻ.
    public static let okina = "\u{2BB}"
    /// ʼ U+02BC, the tutuq belgisi.
    public static let tutuq = "\u{2BC}"

    /// Converts `text` from one script to another; `from == to` (after detection) returns the text unchanged.
    public static func convert(_ text: String, from: SourceScript, to: Script, options: Options = .default) -> String {
        let units = Array(text.utf16)
        let out = convertUTF16(units, from: from, to: to, options: options)
        // the engine never splits a surrogate pair, so a valid string stays valid
        return out == units ? text : String(decoding: out, as: UTF16.self)
    }

    /// `convert` on UTF-16 code units.
    public static func convertUTF16(_ text: [UInt16], from: SourceScript, to: Script, options: Options = .default) -> [UInt16] {
        let source = from.script ?? UzTranslitCore.detect(text)
        if source == to { return text }
        let engine = Engine(options)
        let fn: ([UInt16]) -> [UInt16]
        switch (source, to) {
        case (.cyr, _): fn = { engine.cyrToLatin($0, to) }
        case (_, .cyr): fn = { engine.latinToCyr($0, source) }
        case (.lat, .new): fn = { engine.latToNew($0) }
        default: fn = { engine.newToLat($0) } // new → lat
        }
        return options.skipUrls ? withSkips(text, fn) : fn(text)
    }

    /// The script of `text` (SPEC §5.5): `cyr` when Cyrillic letters are the majority, `new` when 2026 letters are
    /// at least as frequent as 1995 digraphs, otherwise `lat` (also for empty or letterless text).
    public static func detect(_ text: String) -> Script {
        UzTranslitCore.detect(Array(text.utf16))
    }

    public static func cyrToLat(_ text: String, options: Options = .default) -> String { convert(text, from: .cyr, to: .lat, options: options) }
    public static func cyrToNew(_ text: String, options: Options = .default) -> String { convert(text, from: .cyr, to: .new, options: options) }
    public static func latToCyr(_ text: String, options: Options = .default) -> String { convert(text, from: .lat, to: .cyr, options: options) }
    public static func newToCyr(_ text: String, options: Options = .default) -> String { convert(text, from: .new, to: .cyr, options: options) }
    public static func latToNew(_ text: String, options: Options = .default) -> String { convert(text, from: .lat, to: .new, options: options) }
    public static func newToLat(_ text: String, options: Options = .default) -> String { convert(text, from: .new, to: .lat, options: options) }
}
