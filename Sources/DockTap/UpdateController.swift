import AppKit
import Sparkle

final class UpdateController: NSObject {
    var onAvailabilityChanged: (() -> Void)?
    private(set) var availableUpdateVersion: String?

    private let logStore: LogStore
    private var controller: SPUStandardUpdaterController!

    init(logStore: LogStore) {
        self.logStore = logStore
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        logStore.append("updater started feedURL=\(controller.updater.feedURL?.absoluteString ?? "-")")
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

extension UpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableUpdateVersion = item.displayVersionString
        logStore.append("update found version=\(item.displayVersionString)")
        onAvailabilityChanged?()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        guard availableUpdateVersion != nil else { return }
        availableUpdateVersion = nil
        onAvailabilityChanged?()
    }
}

extension UpdateController: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }
}
