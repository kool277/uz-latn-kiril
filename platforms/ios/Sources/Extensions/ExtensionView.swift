import SwiftUI
import UniformTypeIdentifiers
import UzTranslitCore
import UzTranslitKit

/// The extensions' screen: target picker, the converted text, Copy / Share (/ Save for files), Cancel / Done.
struct ExtensionView: View {
    @ObservedObject var model: ExtensionModel
    @State private var exporting = false
    @State private var notice: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: "UzTranslit"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { model.cancel() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { model.done() }
                            .disabled(!model.isReady)
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(message)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            ready
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("To", selection: $model.target) {
                ForEach(Script.allCases, id: \.self) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text(verbatim: "\(model.result.from.localizedName) → \(model.result.to.localizedName)")
                Spacer()
                StatsText(characters: model.result.outputStats.characters, words: model.result.outputStats.words)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            ScrollView {
                Text(model.preview)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .fieldBackground()

            if model.isTruncated {
                Text("Showing the first \(ExtensionModel.previewLimit) characters.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Toggle("Plain apostrophe (')", isOn: $model.asciiApostrophe)

            HStack(spacing: 12) {
                Button {
                    model.copyResult()
                    flash("Copied")
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if let url = model.convertedFileURL {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } else {
                    ShareLink(item: model.result.output) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                if model.isFile {
                    Button {
                        exporting = true
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }
                Spacer()
            }
            .buttonStyle(.bordered)

            if let notice {
                Text(notice)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding()
        .fileExporter(isPresented: $exporting, document: model.document, contentType: .plainText,
                      defaultFilename: model.convertedFileName, onCompletion: { result in
                          if case .success = result { flash("Saved") }
                      })
    }

    private func flash(_ text: LocalizedStringKey) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { notice = nil }
        }
    }
}
