import Foundation
import UzTranslitCore

/// The App Group the iOS app shares its settings with the Share and Action extensions through.
public enum AppGroup {
    public static let identifier = "group.uz.jaybi.uztranslit"

    /// The settings store: the App Group's defaults on iOS (shared with the extensions), the app's own elsewhere.
    public static var defaults: UserDefaults {
        #if os(iOS)
        return UserDefaults(suiteName: identifier) ?? .standard
        #else
        return .standard
        #endif
    }
}

/// User settings (Settings screen); stored in ``AppGroup/defaults`` under ``Key``.
public struct ConverterSettings: Equatable, Sendable {
    /// Target alphabet at app start and in the extensions.
    public var defaultTarget: Script
    /// Write ' instead of ʻ and ʼ.
    public var asciiApostrophe: Bool
    public var dictionary: Bool
    public var dropHardSignAfterO: Bool
    public var tsFinal: Bool
    public var skipUrls: Bool

    public init(defaultTarget: Script = .new, asciiApostrophe: Bool = false, dictionary: Bool = true,
                dropHardSignAfterO: Bool = true, tsFinal: Bool = true, skipUrls: Bool = true) {
        self.defaultTarget = defaultTarget
        self.asciiApostrophe = asciiApostrophe
        self.dictionary = dictionary
        self.dropHardSignAfterO = dropHardSignAfterO
        self.tsFinal = tsFinal
        self.skipUrls = skipUrls
    }

    public static let defaults = ConverterSettings()

    /// The engine options these settings stand for (spec defaults unless changed).
    public var options: Options {
        Options(
            okina: asciiApostrophe ? "'" : UzTranslit.okina,
            tutuq: asciiApostrophe ? "'" : UzTranslit.tutuq,
            dropHardSignAfterO: dropHardSignAfterO,
            tsFinal: tsFinal,
            dictionary: dictionary,
            skipUrls: skipUrls
        )
    }

    public enum Key {
        public static let defaultTarget = "uzt.defaultTarget"
        public static let asciiApostrophe = "uzt.asciiApostrophe"
        public static let dictionary = "uzt.dictionary"
        public static let dropHardSignAfterO = "uzt.dropHardSignAfterO"
        public static let tsFinal = "uzt.tsFinal"
        public static let skipUrls = "uzt.skipUrls"
    }

    /// Reads the settings; missing or invalid values fall back to the defaults.
    public static func load(from store: UserDefaults) -> ConverterSettings {
        let d = ConverterSettings.defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { store.object(forKey: key) as? Bool ?? fallback }
        return ConverterSettings(
            defaultTarget: store.string(forKey: Key.defaultTarget).flatMap(Script.init(rawValue:)) ?? d.defaultTarget,
            asciiApostrophe: bool(Key.asciiApostrophe, d.asciiApostrophe),
            dictionary: bool(Key.dictionary, d.dictionary),
            dropHardSignAfterO: bool(Key.dropHardSignAfterO, d.dropHardSignAfterO),
            tsFinal: bool(Key.tsFinal, d.tsFinal),
            skipUrls: bool(Key.skipUrls, d.skipUrls)
        )
    }

    public func save(to store: UserDefaults) {
        store.set(defaultTarget.rawValue, forKey: Key.defaultTarget)
        store.set(asciiApostrophe, forKey: Key.asciiApostrophe)
        store.set(dictionary, forKey: Key.dictionary)
        store.set(dropHardSignAfterO, forKey: Key.dropHardSignAfterO)
        store.set(tsFinal, forKey: Key.tsFinal)
        store.set(skipUrls, forKey: Key.skipUrls)
    }
}
