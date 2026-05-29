import AppKit
import Sparkle

final class UpdateController: NSObject {
    var onAvailabilityChanged: (() -> Void)?
    var stopBeforeUpdate: ((@escaping (Bool) -> Void) -> Void)?
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

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        logStore.append("update relaunch waiting for closed-lid stop gate version=\(item.displayVersionString)")
        runStopGateBeforeUpdate(version: item.displayVersionString) { success in
            if success {
                installHandler()
            }
        }
        return true
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        logStore.append("update-on-quit waiting for closed-lid stop gate version=\(item.displayVersionString)")
        runStopGateBeforeUpdate(version: item.displayVersionString) { success in
            if success {
                immediateInstallHandler()
            }
        }
        return true
    }

    private func runStopGateBeforeUpdate(version: String, completion: @escaping (Bool) -> Void) {
        guard let stopBeforeUpdate else {
            completion(true)
            return
        }

        stopBeforeUpdate { [weak self] success in
            guard let self else {
                completion(success)
                return
            }

            if success {
                self.logStore.append("update closed-lid stop gate passed version=\(version)")
            } else {
                self.logStore.append("update blocked because closed-lid stop gate failed version=\(version)")
                self.showUpdateBlockedAlert()
            }

            completion(success)
        }
    }

    private func showUpdateBlockedAlert() {
        let alert = NSAlert()
        alert.messageText = AppText.ClosedLid.updateBlockedTitle
        alert.informativeText = "\(AppText.ClosedLid.updateBlockedBody)\n\n\(AppText.ClosedLid.manualRecovery)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension UpdateController: SPUStandardUserDriverDelegate {
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        true
    }
}
