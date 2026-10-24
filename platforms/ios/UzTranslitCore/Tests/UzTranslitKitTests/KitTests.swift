import Foundation
import XCTest
import UzTranslitCore
@testable import UzTranslitKit

final class TextStatsTests: XCTestCase {
    func testCounts() {
        XCTAssertEqual(TextStats(""), .empty)
        XCTAssertEqual(TextStats("  \n\t "), TextStats(characters: 5, words: 0))
        XCTAssertEqual(TextStats("Salom, dunyo!"), TextStats(characters: 13, words: 2))
        // JavaScript whitespace separates words; U+0085 and U+200B do not (as in the web app)
        XCTAssertEqual(TextStats("a\u{A0}b\u{3000}c\u{2028}d").words, 4)
        XCTAssertEqual(TextStats("a\u{85}b\u{200B}c").words, 1)
        // characters are grapheme clusters
        XCTAssertEqual(TextStats("e\u{301}\u{1F600}").characters, 2)
    }
}

final class ConversionTests: XCTestCase {
    func testExplicitDirection() {
        let r = Conversion.run("Toshkent", source: .lat, target: .new, options: .default)
        XCTAssertEqual(r.from, .lat)
        XCTAssertEqual(r.to, .new)
        XCTAssertFalse(r.detected)
        XCTAssertEqual(r.output, UzTranslit.latToNew("Toshkent"))
        XCTAssertEqual(r.inputStats, TextStats("Toshkent"))
        XCTAssertEqual(r.outputStats, TextStats(r.output))
    }

    func testAutoDetects() {
        let text = "Тошкент шаҳри"
        let r = Conversion.run(text, source: .auto, target: .lat, options: .default)
        XCTAssertEqual(r.from, .cyr)
        XCTAssertEqual(r.to, .lat)
        XCTAssertTrue(r.detected)
        XCTAssertEqual(r.output, UzTranslit.cyrToLat(text))
    }

    func testAutoInTargetScriptGoesToTheOtherAlphabet() {
        XCTAssertTrue(Conversion.direction(for: "Тошкент", source: .auto, target: .cyr) == (.cyr, .new))
        XCTAssertTrue(Conversion.direction(for: "Toşkent", source: .auto, target: .new) == (.new, .cyr))
        XCTAssertTrue(Conversion.direction(for: "Toshkent", source: .auto, target: .lat) == (.lat, .cyr))
        // an explicit source is never changed, even when it equals the target
        XCTAssertTrue(Conversion.direction(for: "Toshkent", source: .lat, target: .lat) == (.lat, .lat))
        XCTAssertEqual(Conversion.run("Toshkent", source: .lat, target: .lat, options: .default).output, "Toshkent")
    }

    func testSwapWithoutText() {
        XCTAssertTrue(Conversion.swapped(source: .lat, target: .new, lastUsed: nil) == (.new, .lat))
        XCTAssertTrue(Conversion.swapped(source: .auto, target: .cyr, lastUsed: nil) == (.cyr, .lat))
    }

    func testSwapReversesTheDirectionUsed() {
        // auto-detected Cyrillic → Latin 1995: swap converts Latin 1995 back to Cyrillic
        let detected = Conversion.run("Тошкент", source: .auto, target: .lat, options: .default)
        XCTAssertTrue(Conversion.swapped(source: .auto, target: .lat, lastUsed: detected) == (.lat, .cyr))
        // text already in the target script went to the other alphabet: swap follows what was done
        let redirected = Conversion.run("Toşkent", source: .auto, target: .new, options: .default)
        XCTAssertEqual(redirected.to, .cyr)
        XCTAssertTrue(Conversion.swapped(source: .auto, target: .new, lastUsed: redirected) == (.cyr, .new))
        // and the result converts back
        let back = Conversion.run(redirected.output, source: .cyr, target: .new, options: .default)
        XCTAssertEqual(back.output, "Toşkent")
    }
}

final class SettingsTests: XCTestCase {
    private var suite = ""
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "uztranslit.tests.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        store.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaultsAreTheSpecDefaults() {
        let s = ConverterSettings.load(from: store)
        XCTAssertEqual(s, ConverterSettings.defaults)
        XCTAssertEqual(s.defaultTarget, .new)
        XCTAssertEqual(s.options, Options.default)
    }

    func testRoundTrip() {
        let s = ConverterSettings(defaultTarget: .cyr, asciiApostrophe: true, dictionary: false,
                                  dropHardSignAfterO: false, tsFinal: false, skipUrls: false)
        s.save(to: store)
        XCTAssertEqual(ConverterSettings.load(from: store), s)
        XCTAssertEqual(s.options, Options(okina: "'", tutuq: "'", dropHardSignAfterO: false, tsFinal: false,
                                          dictionary: false, skipUrls: false))
    }

    func testInvalidValuesFallBack() {
        store.set("klingon", forKey: ConverterSettings.Key.defaultTarget)
        store.set("yes", forKey: ConverterSettings.Key.dictionary)
        let s = ConverterSettings.load(from: store)
        XCTAssertEqual(s.defaultTarget, .new)
        XCTAssertTrue(s.dictionary)
    }
}

final class TextFileTests: XCTestCase {
    func testNames() {
        XCTAssertEqual(TextFile.convertedName(for: "matn.txt", target: .new), "matn-new.txt")
        XCTAssertEqual(TextFile.convertedName(for: "hujjat.v2.md", target: .cyr), "hujjat.v2-cyr.md")
        XCTAssertEqual(TextFile.convertedName(for: "README", target: .lat), "README-lat")
        XCTAssertEqual(TextFile.convertedName(for: ".hidden", target: .lat), ".hidden-lat")
        XCTAssertEqual(TextFile.convertedName(for: "", target: .new), "text-new.txt")
        XCTAssertTrue(TextFile.isSupported(fileName: "a.TXT"))
        XCTAssertTrue(TextFile.isSupported(fileName: "subtitles.srt"))
        XCTAssertFalse(TextFile.isSupported(fileName: "photo.jpg"))
        XCTAssertFalse(TextFile.isSupported(fileName: "txt"))
    }

    func testUTF8() {
        let text = "Oʻzbek \u{1F600}"
        let plain = TextFile.decode(Array(text.utf8))
        XCTAssertEqual(plain, DecodedText(text: text, encoding: .utf8, byteOrderMark: false))
        XCTAssertEqual(TextFile.encode(text, like: plain), Array(text.utf8))
        let bom = TextFile.decode([0xEF, 0xBB, 0xBF] + Array(text.utf8))
        XCTAssertEqual(bom, DecodedText(text: text, encoding: .utf8, byteOrderMark: true))
        XCTAssertEqual(TextFile.encode(text, like: bom), [0xEF, 0xBB, 0xBF] + Array(text.utf8))
    }

    func testUTF16() {
        let text = "Ўзбек ʻ"
        let le = [UInt8]([0xFF, 0xFE]) + text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        let be = [UInt8]([0xFE, 0xFF]) + text.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        let dle = TextFile.decode(le), dbe = TextFile.decode(be)
        XCTAssertEqual(dle, DecodedText(text: text, encoding: .utf16LE, byteOrderMark: true))
        XCTAssertEqual(dbe, DecodedText(text: text, encoding: .utf16BE, byteOrderMark: true))
        XCTAssertEqual(TextFile.encode(text, like: dle), le)
        XCTAssertEqual(TextFile.encode(text, like: dbe), be)
        // no byte-order mark: recognised by the zero bytes of ASCII text
        let ascii = "Salom dunyo, salom!"
        let noBom = ascii.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        XCTAssertEqual(TextFile.decode(noBom), DecodedText(text: ascii, encoding: .utf16LE, byteOrderMark: false))
    }

    func testWindows1251() {
        // "Ўзбек ёзуви" in Windows-1251: not valid UTF-8, read as the Cyrillic code page
        let bytes: [UInt8] = [0xA1, 0xE7, 0xE1, 0xE5, 0xEA, 0x20, 0xB8, 0xE7, 0xF3, 0xE2, 0xE8]
        let d = TextFile.decode(bytes)
        XCTAssertEqual(d, DecodedText(text: "Ўзбек ёзуви", encoding: .windows1251, byteOrderMark: false))
        XCTAssertEqual(TextFile.windows1251.count, 128)
        // written back as UTF-8 with a BOM
        XCTAssertEqual(TextFile.encode("Oʻzbek", like: d), [0xEF, 0xBB, 0xBF] + Array("Oʻzbek".utf8))
    }

    func testEveryByteSurvives() {
        // a legacy file never loses a byte: every byte maps to a distinct character
        let all = (0...255).map { UInt8($0) }
        let d = TextFile.decode(all)
        XCTAssertEqual(d.encoding, .windows1251)
        XCTAssertEqual(Set(d.text.unicodeScalars).count, 256)
    }
}
