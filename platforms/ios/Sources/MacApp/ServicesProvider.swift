import AppKit
import UzTranslitCore
import UzTranslitKit

/// Services menu ▸ "Convert to Yangi lotin" (NSServices in Config/MacApp-Info.plist, NSMessage convertToNew):
/// replaces the selected text in any app with its Latin 2026 spelling, using the app's settings. AppKit delivers
/// service requests on the main thread.
@MainActor
final class ServicesProvider: NSObject {
    @objc func convertToNew(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string) else {
            error.pointee = "UzTranslit: the selection contains no text." as NSString
            return
        }
        let options = ConverterSettings.load(from: AppGroup.defaults).options
        let converted = UzTranslit.convert(text, from: .auto, to: .new, options: options)
        pboard.clearContents()
        pboard.setString(converted, forType: .string)
    }
}
