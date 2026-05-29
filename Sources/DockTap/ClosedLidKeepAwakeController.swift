import AppKit
import DockTapClosedLidIPC
import Foundation

final class ClosedLidKeepAwakeController {
    var onStateChanged: (() -> Void)?

    private(set) var state: ClosedLidKeepAwakeState = .off {
        didSet {
            if oldValue != state {
                onStateChanged?()
            }
        }
    }

    private let settingsStore: SettingsStore
    private let helperClient: ClosedLidHelperClienting
    private let logStore: LogStore

    private var renewalTimer: Timer?
    private var stopTimeoutTimer: Timer?
    private var activeToken: String?
    private var pendingStopCompletions: [(Bool, String?) -> Void] = []
    private var isStopInFlight = false
    private var stopFailureAlertRequested = false
    private var activeStopReason = "unknown"
    private var stopRequestedDuringStart = false

    var requiresStopGate: Bool {
        state.canStopSession || isStopInFlight
    }

    init(
        settingsStore: SettingsStore,
        helperClient: ClosedLidHelperClienting,
        logStore: LogStore
    ) {
        self.settingsStore = settingsStore
        self.helperClient = helperClient
        self.logStore = logStore
    }

    func refreshStatus() {
        helperClient.status { [weak self] result in
            self?.applyStatus(result)
        }
    }

    func enableForOneHour() {
        start(duration: 3600, logMode: "timed")
    }

    func enableIndefinitely() {
        start(duration: nil, logMode: "indefinite")
    }

    func stopNow() {
        stopActiveSession(reason: "menu", showFailureAlert: true) { _, _ in }
    }

    func stopBeforeTermination(reason: String, completion: @escaping (Bool, String?) -> Void) {
        guard state.canStopSession || isStopInFlight else {
            completion(true, nil)
            return
        }

        stopActiveSession(reason: reason, showFailureAlert: true, completion: completion)
    }

    func openApprovalSettings() {
        helperClient.openApprovalSettings()
    }

    func invalidate() {
        renewalTimer?.invalidate()
        stopTimeoutTimer?.invalidate()
        helperClient.invalidate()
    }

    private func start(duration: TimeInterval?, logMode: String) {
        guard state.canStartSession else {
            logStore.append("closed-lid start ignored state=\(state.logValue)")
            return
        }

        guard confirmFirstUseWarningIfNeeded() else {
            logStore.append("closed-lid start canceled before helper registration")
            return
        }

        state = .starting
        logStore.append("closed-lid start requested mode=\(logMode)")

        helperClient.prepareForUse { [weak self] result in
            guard let self else { return }
            switch result {
            case .ready:
                self.startPreparedSession(duration: duration)
            case .requiresApproval:
                if self.finishDeferredStopWithoutSession(
                    logMessage: "closed-lid helper preparation requires approval while stop pending"
                ) {
                    return
                }
                self.state = .requiresApproval
                self.logStore.append("closed-lid helper requires approval")
                self.showApprovalRequiredAlert()
            case .notFound(let message), .failure(let message):
                if self.finishDeferredStopWithoutSession(
                    logMessage: "closed-lid helper preparation failed while stop pending: \(message)"
                ) {
                    return
                }
                self.state = .error(message)
                self.logStore.append("closed-lid helper preparation failed: \(message)")
            case .unsafeActiveSession(let message):
                if self.finishDeferredStopWithRestoreRequired(
                    message: message,
                    logMessage: "closed-lid helper preparation could not confirm restore while stop pending: \(message)"
                ) {
                    return
                }
                self.clearActiveSession()
                self.state = .stopFailed(message)
                self.logStore.append(
                    "closed-lid helper preparation could not confirm restore: \(message); \(AppText.ClosedLid.manualRecovery)"
                )
            }
        }
    }

    private func startPreparedSession(duration: TimeInterval?) {
        helperClient.start(duration: duration) { [weak self] result in
            guard let self else { return }
            switch result {
            case .started(let session):
                if self.finishDeferredStopAfterStart(session) {
                    return
                }
                self.applyActiveSession(session)
                self.logStore.append("closed-lid active mode=\(session.logMode)")
            case .alreadyActive(let session):
                if self.finishDeferredStopAfterStart(session) {
                    return
                }
                self.applyActiveSession(session)
                self.logStore.append("closed-lid helper already active mode=\(session.logMode)")
            case .failedWithActiveSession(let session, let message):
                self.logStore.append("closed-lid start failed with active lease: \(message)")
                if self.finishDeferredStopAfterStart(session) {
                    return
                }
                self.stopAfterFailedStart(session)
            case .requiresApproval:
                if self.stopRequestedDuringStart {
                    self.stopRequestedDuringStart = false
                    if self.isStopInFlight {
                        self.completeStop(success: true, message: nil)
                    } else {
                        self.state = .off
                    }
                    return
                }
                if self.isStopInFlight {
                    self.completeStop(success: true, message: nil)
                    return
                }
                self.state = .requiresApproval
                self.logStore.append("closed-lid helper requires approval")
                self.showApprovalRequiredAlert()
            case .failure(let message):
                if self.stopRequestedDuringStart {
                    self.stopRequestedDuringStart = false
                    if self.isStopInFlight {
                        self.completeStop(success: true, message: nil)
                    } else {
                        self.clearActiveSession()
                        self.state = .off
                    }
                    return
                }
                if self.isStopInFlight {
                    self.completeStop(success: true, message: nil)
                    return
                }
                self.clearActiveSession()
                self.state = .error(message)
                self.logStore.append("closed-lid start failed: \(message)")
            }
        }
    }

    private func applyStatus(_ result: ClosedLidHelperStatusResult) {
        switch result {
        case .inactive:
            clearActiveSession()
            state = .off
        case .active(let session):
            applyActiveSession(session)
            logStore.append("closed-lid helper status active mode=\(session.logMode)")
        case .failureWithActiveSession(let session, let message):
            applyActiveSessionError(session, message: message)
            logStore.append("closed-lid status failed with active lease: \(message)")
        case .requiresApproval:
            clearActiveSession()
            state = .requiresApproval
        case .failure(let message):
            clearActiveSession()
            state = .error(message)
            logStore.append("closed-lid status failed: \(message)")
        }
    }

    private func applyActiveSession(_ session: ClosedLidHelperSession) {
        activeToken = session.token
        switch session.mode {
        case .timed:
            state = .activeTimed(endDate: session.endDate ?? Date())
        case .indefinite:
            state = .activeIndefinite
        }
        startRenewalTimer()
    }

    private func applyActiveSessionError(_ session: ClosedLidHelperSession, message: String) {
        activeToken = session.token
        renewalTimer?.invalidate()
        renewalTimer = nil
        state = .errorWithActiveSession(message)
    }

    private func stopAfterFailedStart(_ session: ClosedLidHelperSession) {
        activeToken = session.token
        stopActiveSession(reason: "startFailure", showFailureAlert: true) { _, _ in }
    }

    private func clearActiveSession() {
        activeToken = nil
        renewalTimer?.invalidate()
        renewalTimer = nil
    }

    private func startRenewalTimer() {
        guard renewalTimer == nil else {
            return
        }

        let timer = Timer(
            timeInterval: ClosedLidIPCConstants.renewalIntervalSeconds,
            target: self,
            selector: #selector(renewLease),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        renewalTimer = timer
    }

    @objc func renewLease() {
        guard state.isActive, let activeToken else {
            clearActiveSession()
            return
        }

        helperClient.renewLease(token: activeToken) { [weak self] result in
            guard let self else { return }
            switch result {
            case .renewed:
                break
            case .inactive:
                self.logStore.append("closed-lid helper reports inactive during renewal")
                self.clearActiveSession()
                self.state = .off
            case .requiresApproval:
                self.clearActiveSession()
                self.state = .requiresApproval
                self.logStore.append("closed-lid helper requires approval during renewal")
            case .failure(let message):
                self.renewalTimer?.invalidate()
                self.renewalTimer = nil
                self.state = .errorWithActiveSession(message)
                self.logStore.append("closed-lid renewal failed: \(message)")
            }
        }
    }

    private func stopActiveSession(
        reason: String,
        showFailureAlert: Bool,
        completion: @escaping (Bool, String?) -> Void
    ) {
        pendingStopCompletions.append(completion)
        stopFailureAlertRequested = stopFailureAlertRequested || showFailureAlert

        if case .starting = state, activeToken == nil {
            deferStopUntilStartCompletes(reason: reason)
            return
        }

        guard !isStopInFlight else {
            return
        }

        isStopInFlight = true
        activeStopReason = reason
        renewalTimer?.invalidate()
        renewalTimer = nil
        state = .stopping
        logStore.append("closed-lid stop requested reason=\(reason)")

        armStopTimeout()
        helperClient.stop(token: activeToken, reason: reason) { [weak self] result in
            guard let self, self.isStopInFlight else { return }
            switch result {
            case .stopped:
                self.logStore.append("closed-lid stopped reason=\(reason)")
                self.completeStop(success: true, message: nil)
            case .requiresApproval:
                self.completeStop(success: false, message: "helper approval required")
            case .failure(let message):
                self.completeStop(success: false, message: message)
            }
        }
    }

    private func deferStopUntilStartCompletes(reason: String) {
        guard !isStopInFlight else {
            return
        }

        isStopInFlight = true
        stopRequestedDuringStart = true
        activeStopReason = reason
        renewalTimer?.invalidate()
        renewalTimer = nil
        state = .stopping
        logStore.append("closed-lid stop deferred until start completes reason=\(reason)")
        armStopTimeout()
    }

    private func finishDeferredStopAfterStart(_ session: ClosedLidHelperSession) -> Bool {
        guard stopRequestedDuringStart, activeToken == nil else {
            return false
        }

        activeToken = session.token
        logStore.append("closed-lid start completed while stop pending; stopping active session")
        helperClient.stop(token: session.token, reason: activeStopReason) { [weak self] result in
            guard let self, self.stopRequestedDuringStart else { return }
            self.stopRequestedDuringStart = false
            switch result {
            case .stopped:
                self.logStore.append("closed-lid stopped reason=\(self.activeStopReason)")
                self.completeDeferredStop(success: true, message: nil)
            case .requiresApproval:
                self.completeDeferredStop(success: false, message: "helper approval required")
            case .failure(let message):
                self.completeDeferredStop(success: false, message: message)
            }
        }
        return true
    }

    private func finishDeferredStopWithoutSession(logMessage: String) -> Bool {
        guard stopRequestedDuringStart || isStopInFlight else {
            return false
        }

        stopRequestedDuringStart = false
        clearActiveSession()
        logStore.append(logMessage)

        if isStopInFlight {
            completeStop(success: true, message: nil)
        } else {
            state = .off
        }
        return true
    }

    private func finishDeferredStopWithRestoreRequired(message: String, logMessage: String) -> Bool {
        guard stopRequestedDuringStart || isStopInFlight else {
            return false
        }

        stopRequestedDuringStart = false
        clearActiveSession()
        logStore.append(logMessage)

        if isStopInFlight {
            completeStop(success: false, message: message)
        } else {
            state = .stopFailed(message)
            logStore.append("closed-lid deferred stop failed: \(message); \(AppText.ClosedLid.manualRecovery)")
            if stopFailureAlertRequested {
                showStopFailureAlert(message: message)
            }
        }
        return true
    }

    private func completeDeferredStop(success: Bool, message: String?) {
        if isStopInFlight {
            completeStop(success: success, message: message)
            return
        }

        if success {
            activeToken = nil
            state = .off
        } else {
            let failureMessage = message ?? "helper did not confirm pmset disablesleep 0"
            state = .stopFailed(failureMessage)
            logStore.append("closed-lid deferred stop failed: \(failureMessage); \(AppText.ClosedLid.manualRecovery)")
        }
    }

    private func armStopTimeout() {
        stopTimeoutTimer?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: false) { [weak self] _ in
            guard let self, self.isStopInFlight else { return }
            self.completeStop(
                success: false,
                message: "timed out waiting for helper to confirm pmset disablesleep 0"
            )
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        stopTimeoutTimer = timer
    }

    private func completeStop(success: Bool, message: String?) {
        stopTimeoutTimer?.invalidate()
        stopTimeoutTimer = nil
        isStopInFlight = false

        if success {
            activeToken = nil
            state = .off
        } else {
            let failureMessage = message ?? "helper did not confirm pmset disablesleep 0"
            state = .stopFailed(failureMessage)
            logStore.append("closed-lid stop failed: \(failureMessage); \(AppText.ClosedLid.manualRecovery)")
            if stopFailureAlertRequested {
                showStopFailureAlert(message: failureMessage)
            }
        }

        let completions = pendingStopCompletions
        pendingStopCompletions = []
        stopFailureAlertRequested = false
        completions.forEach { $0(success, message) }
    }

    private func confirmFirstUseWarningIfNeeded() -> Bool {
        guard !settingsStore.hasSeenClosedLidWarning else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = AppText.ClosedLid.warningTitle
        alert.informativeText = AppText.ClosedLid.warningBody
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.ClosedLid.warningContinue)
        alert.addButton(withTitle: AppText.ClosedLid.warningCancel)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        settingsStore.hasSeenClosedLidWarning = true
        return true
    }

    private func showApprovalRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = AppText.ClosedLid.helperApprovalRequired
        alert.informativeText = AppText.ClosedLid.helperApprovalBody
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.ClosedLid.openLoginItemsSettings)
        alert.addButton(withTitle: AppText.ClosedLid.warningCancel)

        if alert.runModal() == .alertFirstButtonReturn {
            helperClient.openApprovalSettings()
        }
    }

    private func showStopFailureAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = AppText.ClosedLid.stopFailureTitle
        alert.informativeText = AppText.ClosedLid.stopFailureBody(message)
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private extension ClosedLidKeepAwakeState {
    var logValue: String {
        switch self {
        case .off:
            return "off"
        case .starting:
            return "starting"
        case .activeTimed:
            return "activeTimed"
        case .activeIndefinite:
            return "activeIndefinite"
        case .stopping:
            return "stopping"
        case .requiresApproval:
            return "requiresApproval"
        case .error:
            return "error"
        case .errorWithActiveSession:
            return "errorWithActiveSession"
        case .stopFailed:
            return "stopFailed"
        }
    }
}

private extension ClosedLidHelperSession {
    var logMode: String {
        switch mode {
        case .timed:
            return "timed"
        case .indefinite:
            return "indefinite"
        }
    }
}
