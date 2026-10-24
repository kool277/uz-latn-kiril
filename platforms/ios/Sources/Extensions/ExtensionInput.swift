import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UzTranslitKit

/// What the host app handed to the extension.
enum SharedInput {
    case text(String)
    /// A plain-text file: its name and decoded contents (the encoding is kept for saving the result).
    case file(name: String, decoded: DecodedText)

    var text: String {
        switch self {
        case .text(let text): return text
        case .file(_, let decoded): return decoded.text
        }
    }
}

enum ExtensionInputError: Error {
    case noText
    case unsupportedFile
    case fileTooLarge
    case unreadable

    var message: LocalizedStringKey {
        switch self {
        case .noText: return "No text to convert."
        case .unsupportedFile: return "Only text and plain-text files (.txt, .md, .csv, .srt) can be converted."
        case .fileTooLarge: return "The file is too large."
        case .unreadable: return "The file could not be read."
        }
    }
}

/// Reads the shared item: a file (public.file-url, or a public.plain-text item delivered as a file), else text
/// (public.plain-text), else the item's attributed content text.
enum ExtensionInput {
    static func load(from items: [NSExtensionItem]) async throws -> SharedInput {
        let providers = items.flatMap { $0.attachments ?? [] }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            let item = try await loadItem(provider, UTType.fileURL)
            if let url = fileURL(from: item) { return try readFile(url) }
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            let item = try await loadItem(provider, UTType.plainText)
            if let text = item as? String { return .text(text) }
            if let text = item as? NSAttributedString { return .text(text.string) }
            if let url = fileURL(from: item) { return try readFile(url) }
            if let data = item as? Data {
                return try decode(data, name: provider.suggestedName.map { $0.contains(".") ? $0 : $0 + ".txt" } ?? "text.txt")
            }
        }
        if let text = items.lazy.compactMap({ $0.attributedContentText?.string }).first(where: { !$0.isEmpty }) {
            return .text(text)
        }
        throw ExtensionInputError.noText
    }

    private static func loadItem(_ provider: NSItemProvider, _ type: UTType) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item)
                }
            }
        }
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL, url.isFileURL { return url }
        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL { return url }
        return nil
    }

    private static func readFile(_ url: URL) throws -> SharedInput {
        let name = url.lastPathComponent
        let conformsToText = UTType(filenameExtension: url.pathExtension)?.conforms(to: .plainText) ?? false
        guard TextFile.isSupported(fileName: name) || conformsToText else { throw ExtensionInputError.unsupportedFile }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > TextFile.maxBytes {
            throw ExtensionInputError.fileTooLarge
        }
        guard let data = try? Data(contentsOf: url) else { throw ExtensionInputError.unreadable }
        return try decode(data, name: name)
    }

    private static func decode(_ data: Data, name: String) throws -> SharedInput {
        guard data.count <= TextFile.maxBytes else { throw ExtensionInputError.fileTooLarge }
        return .file(name: name, decoded: TextFile.decode([UInt8](data)))
    }
}

/// The converted file for the Save button (fileExporter).
struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
