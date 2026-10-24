import SwiftUI
import UzTranslitCore
import UzTranslitKit

/// Settings: default target, apostrophe style and the rules; shared with the extensions (App Group).
struct SettingsView: View {
    @ObservedObject var model: ConverterModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Picker("Default target alphabet", selection: $model.settings.defaultTarget) {
                    ForEach(Script.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
            } footer: {
                Text("Used when the app starts and by the Share and Action extensions.")
            }

            Section("Apostrophe style") {
                Picker("Apostrophe style", selection: $model.settings.asciiApostrophe) {
                    Text("Uzbek marks ʻ ʼ (U+02BB, U+02BC)").tag(false)
                    Text("Plain apostrophe ' (U+0027)").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Rules") {
                Toggle("Loanword dictionary: obyekt → объект, sirk → цирк", isOn: $model.settings.dictionary)
                Toggle("ўъ → oʻ: мўъжиза → moʻjiza", isOn: $model.settings.dropHardSignAfterO)
                Toggle("Word-final -ts → ц: abzats → абзац", isOn: $model.settings.tsFinal)
                Toggle("Leave URLs and e-mails unchanged", isOn: $model.settings.skipUrls)
            }

            Section("About") {
                Text("Latin 2026: law OʻRQ-1184 of 21 October 2026 — Oʻ → Ö, Gʻ → Ğ, Sh → Ş, Ch → Ç.")
                LabeledContent("Version", value: Self.version)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle(Text("Settings"))
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #endif
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? UzTranslit.version
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}
