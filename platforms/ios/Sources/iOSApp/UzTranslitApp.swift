import SwiftUI

@main
struct UzTranslitApp: App {
    @StateObject private var model = ConverterModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ConverterView(model: model)
            }
        }
    }
}
