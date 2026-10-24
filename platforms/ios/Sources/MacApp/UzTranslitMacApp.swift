import AppKit
import SwiftUI

/// The macOS app: the same main window as on iOS, Settings (⌘,), and the Services menu item.
@main
struct UzTranslitMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ConverterModel()

    var body: some Scene {
        Window(Text(verbatim: "UzTranslit"), id: "main") {
            NavigationStack {
                ConverterView(model: model)
            }
            .frame(minWidth: 460, idealWidth: 640, minHeight: 600, idealHeight: 760)
        }
        Settings {
            SettingsView(model: model)
                .frame(width: 480)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: ServicesProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = ServicesProvider()
        services = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
    }
}
