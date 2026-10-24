import SwiftUI
import UIKit

/// Hosts ExtensionView in the extension's principal view controller (no storyboard).
@MainActor
func embedExtensionView(in controller: UIViewController, mode: ExtensionModel.Mode) -> ExtensionModel {
    let model = ExtensionModel(mode: mode, context: controller.extensionContext)
    let host = UIHostingController(rootView: ExtensionView(model: model))
    controller.addChild(host)
    host.view.frame = controller.view.bounds
    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    controller.view.addSubview(host.view)
    host.didMove(toParent: controller)
    return model
}
