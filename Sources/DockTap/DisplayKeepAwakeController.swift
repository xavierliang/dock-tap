import Foundation
import IOKit.pwr_mgt

protocol DisplaySleepAsserting {
    func acquire() -> IOPMAssertionID?
    func release(_ id: IOPMAssertionID) -> Bool
}

/// Public, unprivileged IOKit API. Does not change password policy or synthesize input.
final class DisplaySleepAssertion: DisplaySleepAsserting {
    func acquire() -> IOPMAssertionID? {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Dock Tap keeps the display awake during a keep-awake session" as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    func release(_ id: IOPMAssertionID) -> Bool {
        IOPMAssertionRelease(id) == kIOReturnSuccess
    }
}

final class DisplayKeepAwakeController {
    private let settingsStore: SettingsStore
    private let assertion: DisplaySleepAsserting
    private let logStore: LogStore
    private var assertionID: IOPMAssertionID?
    private var sessionActive = false

    private(set) var errorMessage: String?
    var isEnabled: Bool { settingsStore.keepDisplayAwakeDuringSession }
    var isHoldingAssertion: Bool { assertionID != nil }

    init(settingsStore: SettingsStore, logStore: LogStore,
         assertion: DisplaySleepAsserting = DisplaySleepAssertion()) {
        self.settingsStore = settingsStore
        self.logStore = logStore
        self.assertion = assertion
    }

    deinit {
        if let assertionID { _ = assertion.release(assertionID) }
    }

    func setEnabled(_ enabled: Bool) {
        settingsStore.keepDisplayAwakeDuringSession = enabled
        reconcile()
    }

    func updateSessionState(_ state: ClosedLidKeepAwakeState) {
        switch state {
        case .activeTimed, .activeIndefinite, .errorWithActiveSession:
            sessionActive = true
        case .off, .error, .requiresApproval:
            sessionActive = false
        case .starting, .stopping, .stopFailed:
            // Preserve an existing assertion until the helper confirms that the session ended.
            break
        }
        reconcile()
    }

    func invalidate() {
        sessionActive = false
        reconcile()
    }

    /// Also called on menu open to retry an unsuccessful API call without duplicating assertions.
    func reconcile() {
        if isEnabled && sessionActive {
            guard assertionID == nil else { errorMessage = nil; return }
            guard let id = assertion.acquire() else {
                reportFailure(AppText.DisplayKeepAwake.startFailed)
                return
            }
            assertionID = id
            errorMessage = nil
            logStore.append("display idle-sleep assertion acquired")
        } else if let id = assertionID {
            guard assertion.release(id) else {
                // Do not forget a live assertion on failure; keep it available for a retry.
                reportFailure(AppText.DisplayKeepAwake.stopFailed)
                return
            }
            assertionID = nil
            errorMessage = nil
            logStore.append("display idle-sleep assertion released")
        } else {
            errorMessage = nil
        }
    }

    private func reportFailure(_ message: String) {
        if errorMessage != message { logStore.append(message) }
        errorMessage = message
    }
}
