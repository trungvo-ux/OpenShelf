import Foundation
import Combine
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var configured = false
    @Published private(set) var canCheck = false
    @Published var automaticChecks = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticChecks }
    }
    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?
    var feedHost: String? { (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:))?.host }

    func startIfConfigured() {
        guard controller == nil,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.updateCheckInterval = 86400
        configured = true
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            Task { @MainActor in self?.canCheck = change.newValue ?? false }
        }
        controller.startUpdater()
        automaticChecks = controller.updater.automaticallyChecksForUpdates
    }
    func checkForUpdates() { controller?.checkForUpdates(nil) }
}
