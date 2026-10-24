import UIKit

/// Principal class of the Share extension (NSExtensionPrincipalClass in Config/ShareExtension-Info.plist):
/// converts shared text or a .txt file and offers Copy, Share and Save.
final class ShareViewController: UIViewController {
    private var model: ExtensionModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        let model = embedExtensionView(in: self, mode: .share)
        self.model = model
        model.load()
    }
}
