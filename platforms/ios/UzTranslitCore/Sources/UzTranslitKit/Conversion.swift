import UzTranslitCore

/// One conversion as the apps and extensions run it.
public struct ConversionResult: Equatable, Sendable {
    public let input: String
    public let output: String
    /// The source script that was used (detected when the requested source was `auto`).
    public let from: Script
    /// The target that was used; see ``Conversion/run(_:source:target:options:)``.
    public let to: Script
    /// The source was detected rather than chosen.
    public let detected: Bool
    public let inputStats: TextStats
    public let outputStats: TextStats

    public static let empty = ConversionResult(input: "", output: "", from: .lat, to: .new, detected: false,
                                               inputStats: .empty, outputStats: .empty)

    public init(input: String, output: String, from: Script, to: Script, detected: Bool,
                inputStats: TextStats, outputStats: TextStats) {
        self.input = input
        self.output = output
        self.from = from
        self.to = to
        self.detected = detected
        self.inputStats = inputStats
        self.outputStats = outputStats
    }
}

public enum Conversion {
    /// The direction a conversion takes. With `auto`, text already written in the target script is converted to
    /// the other alphabet instead (Cyrillic → Latin 2026, Latin → Cyrillic), as the web app does.
    public static func direction(for text: String, source: SourceScript, target: Script) -> (from: Script, to: Script) {
        guard source == .auto else { return (source.script ?? .lat, target) }
        let from = UzTranslit.detect(text)
        if from == target { return (from, from == .cyr ? .new : .cyr) }
        return (from, target)
    }

    public static func run(_ text: String, source: SourceScript, target: Script, options: Options) -> ConversionResult {
        let (from, to) = direction(for: text, source: source, target: target)
        let output = UzTranslit.convert(text, from: SourceScript(from), to: to, options: options)
        return ConversionResult(input: text, output: output, from: from, to: to, detected: source == .auto,
                                inputStats: TextStats(text), outputStats: TextStats(output))
    }

    /// The source and target after the swap button. With a conversion on screen, the direction it actually took
    /// is reversed (auto-detection chose its source, and maybe its target); otherwise the pickers are swapped,
    /// `auto` counting as Latin 1995.
    public static func swapped(source: SourceScript, target: Script, lastUsed: ConversionResult?) -> (source: SourceScript, target: Script) {
        if let last = lastUsed { return (SourceScript(last.to), last.from) }
        return (SourceScript(target), source.script ?? .lat)
    }
}
