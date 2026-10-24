import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The general pasteboard (app extensions may write to it too); used from the UI, on the main actor.
@MainActor
enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        #endif
    }
}

/// System colours that follow light and dark mode.
enum Palette {
    static var field: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color(nsColor: .textBackgroundColor)
        #endif
    }

    static var fieldBorder: Color {
        #if os(iOS)
        return Color(uiColor: .separator)
        #else
        return Color(nsColor: .separatorColor)
        #endif
    }
}

/// A rounded, bordered box for the text panes.
struct FieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.fieldBorder, lineWidth: 0.5)
            }
    }
}

extension View {
    func fieldBackground() -> some View { modifier(FieldBackground()) }
}

/// "Characters: 12 · Words: 3", as one localized string.
struct StatsText: View {
    let characters: Int
    let words: Int

    var body: some View {
        Text("Characters: \(characters) · Words: \(words)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}
