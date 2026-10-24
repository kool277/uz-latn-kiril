import SwiftUI
import UzTranslitCore
import UzTranslitKit

/// The main screen (iOS and macOS): direction, input, live result, copy / share / paste / clear, counts.
struct ConverterView: View {
    @ObservedObject var model: ConverterModel
    @FocusState private var inputFocused: Bool
    @State private var showSettings = false
    @State private var copied = false
    @ScaledMetric(relativeTo: .body) private var paneHeight: CGFloat = 160

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                directionPickers
                inputPane
                directionLine
                outputPane
                Toggle("Plain apostrophe (')", isOn: $model.settings.asciiApostrophe)
            }
            .padding()
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text(verbatim: "UzTranslit"))
        .overlay(alignment: .bottom) { copiedBadge }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView(model: model) }
        }
        #endif
    }

    // ------------------------------------------------------------ direction

    private var directionPickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From").font(.subheadline).foregroundStyle(.secondary)
            Picker("From", selection: $model.source) {
                ForEach(SourceScript.allCases, id: \.self) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(alignment: .firstTextBaseline) {
                Text("To").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.swap()
                    Haptics.tap()
                } label: {
                    Label("Swap", systemImage: "arrow.up.arrow.down")
                }
                .font(.subheadline)
            }
            Picker("To", selection: $model.target) {
                ForEach(Script.allCases, id: \.self) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// "Detected: Latin 1995 → Cyrillic" or "Latin 1995 → Latin 2026".
    @ViewBuilder private var directionLine: some View {
        if !model.input.isEmpty {
            let r = model.result
            HStack(spacing: 6) {
                if r.detected {
                    Text("Detected: \(r.from.localizedName)")
                    Text(verbatim: "→ \(r.to.localizedName)")
                } else {
                    Text(verbatim: "\(r.from.localizedName) → \(r.to.localizedName)")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // ------------------------------------------------------------ panes

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Input").font(.headline)
                Spacer()
                StatsText(characters: model.result.inputStats.characters, words: model.result.inputStats.words)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.input)
                    .focused($inputFocused)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .accessibilityLabel(Text("Input"))
                if model.input.isEmpty {
                    Text("Type or paste text here — the result appears instantly.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: paneHeight)
            .fieldBackground()
            HStack(spacing: 12) {
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    DispatchQueue.main.async { model.input = text }
                }
                Button(role: .destructive) {
                    model.clear()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(model.input.isEmpty)
                Spacer()
            }
            .buttonStyle(.bordered)
        }
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Result").font(.headline)
                Spacer()
                StatsText(characters: model.result.outputStats.characters, words: model.result.outputStats.words)
            }
            ScrollView {
                Group {
                    if model.output.isEmpty {
                        Text("Result").foregroundStyle(.secondary)
                    } else {
                        Text(model.output).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .frame(height: paneHeight)
            .fieldBackground()
            .accessibilityLabel(Text("Result"))
            HStack(spacing: 12) {
                Button {
                    copy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut(.return, modifiers: .command)
                ShareLink(item: model.output) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Spacer()
            }
            .buttonStyle(.bordered)
            .disabled(model.output.isEmpty)
        }
    }

    // ------------------------------------------------------------ actions

    #if os(iOS)
    /// Settings (a sheet on iOS; the Settings window on the Mac) and Done above the keyboard.
    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { inputFocused = false }
        }
    }
    #endif

    @ViewBuilder private var copiedBadge: some View {
        if copied {
            Text("Copied")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.opacity)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private func copy() {
        guard !model.output.isEmpty else { return }
        Clipboard.copy(model.output)
        Haptics.success()
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { copied = false }
        }
    }
}
