import Combine
import Foundation
import UzTranslitCore
import UzTranslitKit

/// State of the main screen: the text, the direction, the settings and the live result.
@MainActor
final class ConverterModel: ObservableObject {
    @Published var input = "" {
        didSet { if input != oldValue { schedule() } }
    }
    @Published var source: SourceScript = .auto {
        didSet { if source != oldValue { schedule() } }
    }
    @Published var target: Script {
        didSet { if target != oldValue { schedule() } }
    }
    /// Saved on every change (the extensions read the same store).
    @Published var settings: ConverterSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: store)
            if settings.options != oldValue.options { schedule() }
        }
    }
    @Published private(set) var result = ConversionResult.empty

    /// Texts up to this many UTF-16 code units convert on every keystroke; longer ones once typing pauses,
    /// off the main thread.
    static let liveLimit = 50_000

    private let store: UserDefaults
    private var generation = 0
    private var pending: Task<Void, Never>?

    init(store: UserDefaults = AppGroup.defaults) {
        self.store = store
        let settings = ConverterSettings.load(from: store)
        self.settings = settings
        self.target = settings.defaultTarget
    }

    var output: String { result.output }

    func clear() {
        input = ""
    }

    /// Reverses the direction and moves the result into the input, so the text converts back.
    func swap() {
        let previous = result.output
        let lastUsed = input.isEmpty || previous.isEmpty ? nil : result
        let swapped = Conversion.swapped(source: source, target: target, lastUsed: lastUsed)
        source = swapped.source
        target = swapped.target
        if lastUsed != nil { input = previous }
    }

    private func schedule() {
        generation += 1
        let current = generation
        pending?.cancel()
        pending = nil
        let text = input, source = source, target = target, options = settings.options
        if text.isEmpty {
            result = .empty
            return
        }
        if text.utf16.count <= Self.liveLimit {
            result = Conversion.run(text, source: source, target: target, options: options)
            return
        }
        pending = Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let converted = Conversion.run(text, source: source, target: target, options: options)
            await self?.publish(converted, generation: current)
        }
    }

    private func publish(_ converted: ConversionResult, generation: Int) {
        guard generation == self.generation else { return } // a newer edit is on its way
        result = converted
    }
}
