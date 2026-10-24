import XCTest
@testable import UzTranslitCore

/// Differential test against the reference: build/differential.json holds core/js/uztranslit.js's output for random
/// text in every direction with random options (node tools/make_differential.mjs), copied in by sync-fixtures.sh.
final class DifferentialTests: XCTestCase {
    func testMatchesReference() throws {
        guard let diff = try TestData.load(DifferentialFile.self, "differential") else {
            throw XCTSkip("differential.json is not in the test bundle: run `node tools/make_differential.mjs` and "
                + "platforms/ios/scripts/sync-fixtures.sh to compare against the reference")
        }
        var conversions = Tally()
        for c in diff.cases {
            let got = UzTranslit.convert(c.input, from: source(c.from), to: script(c.to), options: c.options.options)
            conversions.check("\(c.from)->\(c.to) \(c.options.options)\n   in   \(Tally.show(c.input))", got: got, want: c.out)
        }
        var detections = Tally()
        for d in diff.detect {
            detections.check("detect \(Tally.show(d.input))", got: UzTranslit.detect(d.input).rawValue, want: d.expect)
        }
        print("differential vs \(diff.reference) (seed \(diff.seed)): conversions \(conversions.passed) passed, "
            + "\(conversions.failed) failed; detections \(detections.passed) passed, \(detections.failed) failed")
        XCTAssertGreaterThan(diff.cases.count, 0)
        XCTAssertEqual(conversions.failed, 0, "\n" + conversions.messages.joined(separator: "\n"))
        XCTAssertEqual(detections.failed, 0, "\n" + detections.messages.joined(separator: "\n"))
        XCTAssertEqual(conversions.passed, diff.cases.count)
        XCTAssertEqual(detections.passed, diff.detect.count)
    }

    /// The same corpus through the UTF-16 entry point (no String round trip).
    func testUTF16EntryPointMatchesReference() throws {
        guard let diff = try TestData.load(DifferentialFile.self, "differential") else {
            throw XCTSkip("differential.json is not in the test bundle")
        }
        var failed = 0
        for c in diff.cases {
            let got = UzTranslit.convertUTF16(Array(c.input.utf16), from: source(c.from), to: script(c.to), options: c.options.options)
            if got != Array(c.out.utf16) { failed += 1 }
        }
        XCTAssertEqual(failed, 0)
    }
}
