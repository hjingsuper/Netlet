import Foundation
import Sparkle

@MainActor
final class UpdateManager: NSObject {
    let isAvailable = Bundle.main.object(
        forInfoDictionaryKey: "NetletDistributionBuild"
    ) as? Bool ?? false

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func start() {
        guard isAvailable else { return }
#if DEBUG
        guard ProcessInfo.processInfo.environment["NETLET_UI_PREVIEW"] != "1" else { return }
#endif
        updaterController.startUpdater()
    }

    func checkForUpdates() {
        guard isAvailable else { return }
        updaterController.checkForUpdates(nil)
    }
}
