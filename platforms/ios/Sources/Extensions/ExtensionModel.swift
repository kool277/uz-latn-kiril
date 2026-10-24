import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UzTranslitCore
import UzTranslitKit

/// State of the Share and Action extensions: load the shared item, convert it (source detected, target from the
/// app's settings), and hand the result back.
@MainActor
final class ExtensionModel: ObservableObject {
    enum Mode {
        /// Share extension: copy, share or save the result.
        case share
        /// Action extension: Done returns the converted text to the host app.
        case action
    }

    enum Phase {
        case loading
        case ready
        case failed(LocalizedStringKey)
    }

    let mode: Mode
    let settings: ConverterSettings
    @Published private(set) var phase: Phase = .loading
    @Published var target: Script {
        didSet { if target != oldValue { convert() } }
    }
    /// The ASCII-apostrophe switch; starts from the app's setting, not saved.
    @Published var asciiApostrophe: Bool {
        didSet { if asciiApostrophe != oldValue { convert() } }
    }
    @Published private(set) var result = ConversionResult.empty
    /// The start of the result (the whole text is copied, shared and saved).
    @Published private(set) var preview = ""
    @Published private(set) var isTruncated = false
    /// The result in the original file's encoding (file input), for Save.
    @Published private(set) var document: TextFileDocument?
    /// The same bytes in a temporary file, for ShareLink.
    @Published private(set) var convertedFileURL: URL?

    private weak var context: NSExtensionContext?
    private var input: SharedInput?

    /// The preview shows at most this many characters.
    static let previewLimit = 20_000

    init(mode: Mode, context: NSExtensionContext?) {
        self.mode = mode
        self.context = context
        let settings = ConverterSettings.load(from: AppGroup.defaults)
        self.settings = settings
        self.target = settings.defaultTarget
        self.asciiApostrophe = settings.asciiApostrophe
    }

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    var isFile: Bool {
        if case .file = input { return true }
        return false
    }

    /// "matn.txt" → "matn-new.txt"
    var convertedFileName: String {
        if case .file(let name, _) = input { return TextFile.convertedName(for: name, target: result.to) }
        return TextFile.convertedName(for: "text.txt", target: result.to)
    }

    func load() {
        let items = (context?.inputItems as? [NSExtensionItem]) ?? []
        Task {
            do {
                input = try await ExtensionInput.load(from: items)
                convert()
                phase = .ready
            } catch let error as ExtensionInputError {
                phase = .failed(error.message)
            } catch {
                phase = .failed(ExtensionInputError.unreadable.message)
            }
        }
    }

    private func convert() {
        guard let input else { return }
        var current = settings
        current.asciiApostrophe = asciiApostrophe
        result = Conversion.run(input.text, source: .auto, target: target, options: current.options)
        let head = result.output.prefix(Self.previewLimit)
        isTruncated = head.endIndex < result.output.endIndex
        preview = isTruncated ? String(head) + "\u{2026}" : result.output
        writeConvertedFile()
    }

    private func writeConvertedFile() {
        guard case .file(_, let decoded) = input else {
            document = nil
            convertedFileURL = nil
            return
        }
        let document = TextFileDocument(data: Data(TextFile.encode(result.output, like: decoded)))
        self.document = document
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UzTranslit", isDirectory: true)
        let url = folder.appendingPathComponent(convertedFileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try document.data.write(to: url, options: .atomic)
            convertedFileURL = url
        } catch {
            convertedFileURL = nil
        }
    }

    func copyResult() {
        Clipboard.copy(result.output)
    }

    /// Done: the action extension returns the converted text (the host may replace the selection with it).
    func done() {
        switch mode {
        case .action:
            let item = NSExtensionItem()
            item.attributedContentText = NSAttributedString(string: result.output)
            item.attachments = [NSItemProvider(item: result.output as NSString, typeIdentifier: UTType.plainText.identifier)]
            context?.completeRequest(returningItems: [item], completionHandler: nil)
        case .share:
            context?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    func cancel() {
        context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}
