import XCTest
@testable import UzTranslitCore

/// Conformance runner for spec/fixtures.json (cases, roundtrips, detect, optional), like core/js/test.js.
final class FixturesTests: XCTestCase {
    func testFixtures() throws {
        guard let fx = try TestData.load(FixtureFile.self, "fixtures") else {
            XCTFail("fixtures.json is not in the test bundle: run platforms/ios/scripts/sync-fixtures.sh first")
            return
        }
        var tally = Tally()

        for c in fx.cases {
            let got = UzTranslit.convert(c.input, from: source(c.from), to: script(c.to))
            tally.check("\(c.id) \(c.from)->\(c.to) \(Tally.show(c.input))", got: got, want: c.out)
        }

        for r in fx.roundtrips {
            let there = UzTranslit.convert(r.input, from: source(r.from), to: script(r.via))
            let back = UzTranslit.convert(there, from: source(r.via), to: script(r.from))
            tally.check("\(r.id) \(r.from)->\(r.via)->\(r.from) via \(Tally.show(there))", got: back, want: r.input)
        }

        for d in fx.detect {
            tally.check("detect \(Tally.show(d.input))", got: UzTranslit.detect(d.input).rawValue, want: d.expect)
        }

        for o in fx.optional {
            let options = o.feature == "asciiApostrophe" ? Options(okina: "'", tutuq: "'") : Options(skipUrls: true)
            let got = UzTranslit.convert(o.input, from: source(o.from), to: script(o.to), options: options)
            tally.check("optional/\(o.feature)", got: got, want: o.out)
        }

        let total = fx.cases.count + fx.roundtrips.count + fx.detect.count + fx.optional.count
        print("\(tally.passed) passed, \(tally.failed) failed (fixtures.json v\(fx.version), UzTranslitCore v\(UzTranslit.version))")
        XCTAssertGreaterThan(total, 0)
        XCTAssertEqual(tally.failed, 0, "\n" + tally.messages.joined(separator: "\n"))
        XCTAssertEqual(tally.passed, total)
    }
}
