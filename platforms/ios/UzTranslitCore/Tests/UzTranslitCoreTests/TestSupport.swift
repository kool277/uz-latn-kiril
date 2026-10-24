import Foundation
import XCTest
@testable import UzTranslitCore

/// The test data in the bundle: copied from the repository by platforms/ios/scripts/sync-fixtures.sh
/// (spec/fixtures.json → fixtures.json, build/differential.json → differential.json). Never hand-copy cases.
enum TestData {
    static func url(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources")
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? {
        guard let url = url(name) else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

/// spec/fixtures.json
struct FixtureFile: Decodable {
    struct Case: Decodable {
        let id: String
        let from: String
        let to: String
        let input: String
        let out: String
        enum CodingKeys: String, CodingKey { case id, from, to, input = "in", out }
    }
    struct Roundtrip: Decodable {
        let id: String
        let from: String
        let via: String
        let input: String
        enum CodingKeys: String, CodingKey { case id, from, via, input = "in" }
    }
    struct Detection: Decodable {
        let input: String
        let expect: String
        enum CodingKeys: String, CodingKey { case input = "in", expect }
    }
    struct OptionalCase: Decodable {
        let feature: String
        let from: String
        let to: String
        let input: String
        let out: String
        enum CodingKeys: String, CodingKey { case feature, from, to, input = "in", out }
    }
    let version: String
    let cases: [Case]
    let roundtrips: [Roundtrip]
    let detect: [Detection]
    let optional: [OptionalCase]
}

/// build/differential.json (tools/make_differential.mjs): the reference's output on random text.
struct DifferentialFile: Decodable {
    struct JSOptions: Decodable {
        let okina: String
        let tutuq: String
        let dropHardSignAfterO: Bool
        let tsFinal: Bool
        let dictionary: Bool
        let skipUrls: Bool
        var options: Options {
            Options(okina: okina, tutuq: tutuq, dropHardSignAfterO: dropHardSignAfterO, tsFinal: tsFinal,
                    dictionary: dictionary, skipUrls: skipUrls)
        }
    }
    struct Case: Decodable {
        let from: String
        let to: String
        let options: JSOptions
        let input: String
        let out: String
        enum CodingKeys: String, CodingKey { case from, to, options, input = "in", out }
    }
    struct Detection: Decodable {
        let input: String
        let expect: String
        enum CodingKeys: String, CodingKey { case input = "in", expect }
    }
    let reference: String
    let seed: Int
    let cases: [Case]
    let detect: [Detection]
}

/// Pass/fail counts; outputs are compared as UTF-16 code units (String == would compare canonical equivalence).
struct Tally {
    private(set) var passed = 0
    private(set) var failed = 0
    private(set) var messages: [String] = []

    mutating func check(_ id: @autoclosure () -> String, got: String, want: String) {
        if Array(got.utf16) == Array(want.utf16) {
            passed += 1
            return
        }
        failed += 1
        if messages.count < 25 {
            messages.append("FAIL \(id())\n   want \(Tally.show(want))\n   got  \(Tally.show(got))")
        }
    }

    /// Debug form with every non-ASCII or invisible code unit as \u{…}.
    static func show(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            if u.value >= 0x20 && u.value < 0x7F && u != "\"" && u != "\\" { out.unicodeScalars.append(u) }
            else { out += "\\u{\(String(u.value, radix: 16, uppercase: true))}" }
        }
        return out + "\""
    }
}

func source(_ s: String) -> SourceScript {
    guard let v = SourceScript(rawValue: s) else { fatalError("unknown script \(s)") }
    return v
}

func script(_ s: String) -> Script {
    guard let v = Script(rawValue: s) else { fatalError("unknown script \(s)") }
    return v
}
