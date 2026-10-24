import UzTranslitCore

/// The encoding a text file was read in.
public enum TextEncoding: String, Sendable {
    case utf8
    case utf16LE
    case utf16BE
    /// Legacy Windows Cyrillic code page; written back as UTF-8 with a byte-order mark, because the converted text
    /// needs letters the code page does not have (ʻ ʼ, қ ғ ҳ, Ö Ğ Ş Ç).
    case windows1251
}

public struct DecodedText: Equatable, Sendable {
    public let text: String
    public let encoding: TextEncoding
    public let byteOrderMark: Bool

    public init(text: String, encoding: TextEncoding, byteOrderMark: Bool) {
        self.text = text
        self.encoding = encoding
        self.byteOrderMark = byteOrderMark
    }
}

/// Reading and writing the plain-text files the Share extension converts (.txt and friends), like the web app:
/// Unicode files keep their encoding and byte-order mark, legacy files become UTF-8 with a BOM.
public enum TextFile {
    /// Largest file the extensions convert (extensions run with little memory).
    public static let maxBytes = 8 * 1024 * 1024

    /// File name extensions treated as plain text.
    public static let extensions: Set<String> = ["txt", "text", "md", "markdown", "csv", "tsv", "srt", "vtt"]

    public static func isSupported(fileName: String) -> Bool {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return false }
        return extensions.contains(String(fileName[fileName.index(after: dot)...]).lowercased())
    }

    /// "matn.txt" → "matn-new.txt" (the target script's id is appended to the base name).
    public static func convertedName(for fileName: String, target: Script) -> String {
        let name = fileName.isEmpty ? "text.txt" : fileName
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "\(name)-\(target.rawValue)" }
        return "\(name[..<dot])-\(target.rawValue)\(name[dot...])"
    }

    public static func decode(_ bytes: [UInt8]) -> DecodedText {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return DecodedText(text: String(decoding: bytes.dropFirst(3), as: UTF8.self), encoding: .utf8, byteOrderMark: true)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return DecodedText(text: utf16(bytes.dropFirst(2), littleEndian: true), encoding: .utf16LE, byteOrderMark: true)
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return DecodedText(text: utf16(bytes.dropFirst(2), littleEndian: false), encoding: .utf16BE, byteOrderMark: true)
        }
        if let le = utf16Guess(bytes) {
            return DecodedText(text: utf16(bytes[...], littleEndian: le), encoding: le ? .utf16LE : .utf16BE, byteOrderMark: false)
        }
        if isValidUTF8(bytes) {
            return DecodedText(text: String(decoding: bytes, as: UTF8.self), encoding: .utf8, byteOrderMark: false)
        }
        let units = bytes.map { $0 < 0x80 ? UInt16($0) : windows1251[Int($0) - 0x80] }
        return DecodedText(text: String(decoding: units, as: UTF16.self), encoding: .windows1251, byteOrderMark: false)
    }

    /// The converted text in the original file's encoding (legacy code pages: UTF-8 with a BOM).
    public static func encode(_ text: String, like original: DecodedText) -> [UInt8] {
        switch original.encoding {
        case .utf8:
            return (original.byteOrderMark ? [0xEF, 0xBB, 0xBF] : []) + Array(text.utf8)
        case .windows1251:
            return [0xEF, 0xBB, 0xBF] + Array(text.utf8)
        case .utf16LE, .utf16BE:
            let le = original.encoding == .utf16LE
            var out: [UInt8] = original.byteOrderMark ? (le ? [0xFF, 0xFE] : [0xFE, 0xFF]) : []
            out.reserveCapacity(out.count + text.utf16.count * 2)
            for u in text.utf16 {
                let hi = UInt8(u >> 8), lo = UInt8(u & 0xFF)
                if le { out.append(lo); out.append(hi) } else { out.append(hi); out.append(lo) }
            }
            return out
        }
    }

    static func isValidUTF8(_ bytes: [UInt8]) -> Bool {
        var decoder = UTF8()
        var it = bytes.makeIterator()
        while true {
            switch decoder.decode(&it) {
            case .scalarValue: continue
            case .emptyInput: return true
            case .error: return false
            }
        }
    }

    /// UTF-16 without a byte-order mark: zero bytes at every other position (true = little endian).
    static func utf16Guess(_ b: [UInt8]) -> Bool? {
        let n = min(b.count, 4096) & ~1
        if n < 4 { return nil }
        var evenZero = 0, oddZero = 0
        for i in stride(from: 0, to: n, by: 2) {
            if b[i] == 0 { evenZero += 1 }
            if b[i + 1] == 0 { oddZero += 1 }
        }
        let half = Double(n / 2)
        if Double(oddZero) > half * 0.3 && Double(evenZero) < half * 0.05 { return true }
        if Double(evenZero) > half * 0.3 && Double(oddZero) < half * 0.05 { return false }
        return nil
    }

    static func utf16(_ bytes: ArraySlice<UInt8>, littleEndian: Bool) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count / 2)
        var i = bytes.startIndex
        while i + 1 < bytes.endIndex {
            let a = UInt16(bytes[i]), b = UInt16(bytes[i + 1])
            units.append(littleEndian ? a | b << 8 : a << 8 | b)
            i += 2
        }
        if i < bytes.endIndex { units.append(0xFFFD) } // odd trailing byte
        return String(decoding: units, as: UTF16.self)
    }

    /// Windows-1251 bytes 0x80…0xBF (WHATWG index; 0x98 is U+0098); 0xC0…0xFF are А…я.
    private static let windows1251High: [UInt16] = [
        0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, 0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
        0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
        0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, 0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
        0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7, 0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457
    ]
    private static let cyrillicAToYa: [UInt16] = Array(0x0410...0x044F)

    /// Windows-1251 bytes 0x80…0xFF.
    static let windows1251: [UInt16] = windows1251High + cyrillicAToYa
}
