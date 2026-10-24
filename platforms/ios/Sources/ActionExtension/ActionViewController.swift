import UIKit

/// Principal class of the Action extension (NSExtensionPrincipalClass in Config/ActionExtension-Info.plist):
/// converts the selected text; Done returns the result to the host app.
final class ActionViewController: UIViewController {
    private var model: ExtensionModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        let model = embedExtensionView(in: self, mode: .action)
        self.model = model
        model.load()
    }
}
