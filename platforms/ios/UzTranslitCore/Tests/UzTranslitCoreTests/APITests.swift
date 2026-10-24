import XCTest
@testable import UzTranslitCore

/// The public surface: defaults, identity, the direction helpers, and UTF-16 (not grapheme) semantics.
/// Expected strings below were produced by core/js/uztranslit.js; conformance itself is FixturesTests' job.
final class APITests: XCTestCase {
    private func assertUnits(_ got: String, _ want: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(got.utf16), Array(want.utf16), "\(Tally.show(got)) != \(Tally.show(want))", file: file, line: line)
    }

    func testDefaultsAreTheSpecs() {
        let o = Options()
        XCTAssertEqual(Array(o.okina.unicodeScalars).map(\.value), [0x2BB])
        XCTAssertEqual(Array(o.tutuq.unicodeScalars).map(\.value), [0x2BC])
        XCTAssertTrue(o.dropHardSignAfterO && o.tsFinal && o.dictionary && o.skipUrls)
        XCTAssertEqual(Options.default, o)
        XCTAssertEqual(Options.asciiApostrophe.okina, "'")
        XCTAssertEqual(Options.asciiApostrophe.tutuq, "'")
    }

    func testSameScriptReturnsTextUnchanged() {
        let text = "Ўзбекистон Oʻzbekiston Özbekiston \u{1F600} e\u{301}"
        for s in Script.allCases {
            assertUnits(UzTranslit.convert(text, from: SourceScript(s), to: s), text)
        }
        // auto resolves first: Cyrillic text to Cyrillic is unchanged too
        assertUnits(UzTranslit.convert("Салом", from: .auto, to: .cyr), "Салом")
    }

    func testEmptyText() {
        for from in SourceScript.allCases {
            for to in Script.allCases {
                XCTAssertEqual(UzTranslit.convert("", from: from, to: to), "")
            }
        }
        XCTAssertEqual(UzTranslit.detect(""), .lat)
    }

    func testDirectionHelpersMatchConvert() {
        let samples = ["Тошкент шаҳри, Isʼhoq", "Toshkent shahri, Is'hoq", "Toşkent şahri, Ishoq", "ШАҲАР Şahar"]
        for t in samples {
            assertUnits(UzTranslit.cyrToLat(t), UzTranslit.convert(t, from: .cyr, to: .lat))
            assertUnits(UzTranslit.cyrToNew(t), UzTranslit.convert(t, from: .cyr, to: .new))
            assertUnits(UzTranslit.latToCyr(t), UzTranslit.convert(t, from: .lat, to: .cyr))
            assertUnits(UzTranslit.newToCyr(t), UzTranslit.convert(t, from: .new, to: .cyr))
            assertUnits(UzTranslit.latToNew(t), UzTranslit.convert(t, from: .lat, to: .new))
            assertUnits(UzTranslit.newToLat(t), UzTranslit.convert(t, from: .new, to: .lat))
            let ascii = Options.asciiApostrophe
            assertUnits(UzTranslit.cyrToLat(t, options: ascii), UzTranslit.convert(t, from: .cyr, to: .lat, options: ascii))
            // auto = detect, then convert
            for to in Script.allCases {
                let detected = SourceScript(UzTranslit.detect(t))
                assertUnits(UzTranslit.convert(t, from: .auto, to: to), UzTranslit.convert(t, from: detected, to: to))
            }
        }
    }

    func testUTF16EntryPointMatchesStringEntryPoint() {
        let t = "Ўзбекистон \u{1F600} https://ex.uz/ш маъно"
        for to in Script.allCases {
            let viaString = UzTranslit.convert(t, from: .cyr, to: to)
            XCTAssertEqual(UzTranslit.convertUTF16(Array(t.utf16), from: .cyr, to: to), Array(viaString.utf16))
        }
    }

    func testCodeUnitsNotGraphemes() {
        // a combining mark is not a letter, so Ш has no next letter here ("Sh"), as in JavaScript
        assertUnits(UzTranslit.cyrToLat("Ш\u{301}"), "Sh\u{301}")
        assertUnits(UzTranslit.cyrToLat("Ш\u{301}А"), "Sh\u{301}A")
        assertUnits(UzTranslit.cyrToLat("Ш\u{1F600}АР"), "Sh\u{1F600}AR")
        assertUnits(UzTranslit.latToCyr("e\u{301}lon"), "э\u{301}лон")
        assertUnits(UzTranslit.newToLat("Ş\u{327}"), "Sh\u{327}")
    }

    func testEmptyMarks() {
        assertUnits(UzTranslit.cyrToLat("ЎҒ", options: Options(okina: "")), "OG")
        assertUnits(UzTranslit.cyrToLat("Ўғ маъно", options: Options(okina: "", tutuq: "")), "Og mano")
    }

    func testSkipUrls() {
        let t = "see https://ex.uz/shahar shahar"
        assertUnits(UzTranslit.latToNew(t), "see https://ex.uz/shahar şahar")
        assertUnits(UzTranslit.latToNew(t, options: Options(skipUrls: false)), "see https://ex.uz/şahar şahar")
    }

    func testDictionaryIsSortedLongestFirst() {
        for bucket in DICT.buckets {
            XCTAssertEqual(bucket.map(\.key.count), bucket.map(\.key.count).sorted(by: >))
        }
        XCTAssertEqual(DICT.buckets.reduce(0) { $0 + $1.count }, DICT_SRC.split(separator: "|").count)
    }
}
