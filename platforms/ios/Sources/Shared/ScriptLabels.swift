import SwiftUI
import UzTranslitCore

// Labels of the scripts (Localizable.xcstrings): Uzbek Avto / Кирилл / Lotin 1995 / Yangi lotin,
// Russian Авто / Кириллица / Латиница 1995 / Новая латиница, English Auto / Cyrillic / Latin 1995 / Latin 2026.

extension Script {
    var label: LocalizedStringKey {
        switch self {
        case .cyr: return "Cyrillic"
        case .lat: return "Latin 1995"
        case .new: return "Latin 2026"
        }
    }

    var localizedName: String {
        switch self {
        case .cyr: return String(localized: "Cyrillic")
        case .lat: return String(localized: "Latin 1995")
        case .new: return String(localized: "Latin 2026")
        }
    }
}

extension SourceScript {
    var label: LocalizedStringKey {
        switch self {
        case .auto: return "Auto"
        case .cyr: return Script.cyr.label
        case .lat: return Script.lat.label
        case .new: return Script.new.label
        }
    }
}
