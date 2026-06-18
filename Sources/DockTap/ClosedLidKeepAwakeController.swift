import AppKit
import DockTapClosedLidIPC
import Foundation

final class ClosedLidKeepAwakeController {
    private enum ApprovalFollowUp {
        static let maxAttempts = 60
        static let retryInterval: TimeInterval = 1
        static let prepareTimeout: TimeInterval = 60
    }

    private enum LidDimming {
        static let minimumRestoredBrightness = 0.40
    }

    var onStateChanged: (() -> Void)?

    private(set) var state: ClosedLidKeepAwakeState = .off {
        didSet {
            if oldValue != state {
                reconcileLidDimming(from: oldValue, to: state)
                onStateChanged?()
            }
        }
    }

    private let settingsStore: SettingsStore
    private let helperClient: ClosedLidHelperClienting
    private let logStore: LogStore
    private let brightnessController: BrightnessControlling
    private let lidObserver: LidStateObserving
    private let approvalFollowUpMaxAttempts: Int
    private let approvalFollowUpRetryInterval: TimeInterval
    private let approvalFollowUpPrepareTimeout: TimeInterval

    /// 合盖压暗前保存的亮度；非 nil 即表示"当前处于压暗状态"，用于幂等恢复。
    private var savedBrightness: Double?

    private var renewalTimer: Timer?
    private var stopTimeoutTimer: Timer?
    private var approvalFollowUpTimeoutTimer: Timer?
    private var activeToken: String?
    private var pendingStopCompletions: [(Bool, String?) -> Void] = []
    private var isStopInFlight = false
    private var stopFailureAlertRequested = false
    private var activeStopReason = "unknown"
    private var stopRequestedDuringStart = false
    private var approvalFollowUpTimer: Timer?
    private var approvalFollowUpDuration: TimeInterval?
    private var approvalFollowUpAttemptsRemaining = 0
    private var approvalFollowUpPrepareInFlight = false
    private var approvalFollowUpGeneration = 0
    private var activeApprovalFollowUpGeneration: Int?
    private var approvalAlertShownForCurrentStart = false

    var requiresStopGate: Bool {
        state.canStopSession || isStopInFlight || hasPendingApprovalFollowUpStart
    }

    init(
        settingsStore: SettingsStore,
        helperClient: ClosedLidHelperClienting,
        logStore: LogStore,
        brightnessController: BrightnessControlling? = nil,
        lidObserver: LidStateObserving? = nil,
        approvalFollowUpMaxAttempts: Int = ApprovalFollowUp.maxAttempts,
        approvalFollowUpRetryInterval: TimeInterval = ApprovalFollowUp.retryInterval,
        approvalFollowUpPrepareTimeout: TimeInterval = ApprovalFollowUp.prepareTimeout
    ) {
        self.settingsStore = settingsStore
        self.helperClient = helperClient
        self.logStore = logStore
        self.brightnessController = brightnessController
            ?? BrightnessController(log: { logStore.append($0) })
        self.lidObserver = lidObserver ?? LidStateObserver()
        self.approvalFollowUpMaxAttempts = approvalFollowUpMaxAttempts
        self.approvalFollowUpRetryInterval = approvalFollowUpRetryInterval
        self.approvalFollowUpPrepareTimeout = approvalFollowUpPrepareTimeout

        self.lidObserver.onLidStateChanged = { [weak self] closed in
            self?.handleLidStateChanged(closed: closed)
        }
    }

    func refreshStatus() {
        guard canApplyStatusRefresh else {
            return
        }

        helperClient.status { [weak self] result in
            guard let self, self.canApplyStatusRefresh else {
                return
            }
            self.applyStatus(result)
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
        guard state.canStopSession || isStopInFlight || hasPendingApprovalFollowUpStart else {
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
        cancelApprovalFollowUp()
        endLidDimming()
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

        approvalFollowUpAttemptsRemaining = approvalFollowUpMaxAttempts
        state = .starting
        approvalAlertShownForCurrentStart = false
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
                self.beginApprovalFollowUp(duration: duration)
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
                self.beginApprovalFollowUp(duration: duration)
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

    private var canApplyStatusRefresh: Bool {
        !isStopInFlight
            && !stopRequestedDuringStart
            && activeApprovalFollowUpGeneration == nil
            && state != .starting
            && state != .stopping
    }

    private var hasPendingApprovalFollowUpStart: Bool {
        activeApprovalFollowUpGeneration != nil
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
        case .unsafeActiveSession(let message):
            clearActiveSession()
            state = .stopFailed(message)
            logStore.append("closed-lid status could not confirm restore: \(message); \(AppText.ClosedLid.manualRecovery)")
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
        cancelApprovalFollowUp()
        approvalAlertShownForCurrentStart = false
        activeToken = session.token
        switch session.mode {
        case .timed:
            state = .activeTimed(endDate: session.endDate ?? Date())
        case .indefinite:
            state = .activeIndefinite
        }
        startRenewalTimer()
        // 合盖监听由 state 的 didSet（reconcileLidDimming）统一驱动，此处不重复触发。
    }

    private func applyActiveSessionError(_ session: ClosedLidHelperSession, message: String) {
        cancelApprovalFollowUp()
        approvalAlertShownForCurrentStart = false
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
        // 合盖监听的结束同样由 state 的 didSet 统一驱动。
    }

    private func beginApprovalFollowUp(duration: TimeInterval?) {
        cancelApprovalFollowUp(resetBudget: false)
        approvalFollowUpGeneration += 1
        activeApprovalFollowUpGeneration = approvalFollowUpGeneration
        approvalFollowUpDuration = duration

        clearActiveSession()
        state = .requiresApproval
        logStore.append("closed-lid helper requires approval")
        showApprovalRequiredAlertIfNeeded()
        armApprovalFollowUpTimeout(generation: approvalFollowUpGeneration)
        pollApprovalFollowUp(generation: approvalFollowUpGeneration)
    }

    private func pollApprovalFollowUp(generation: Int) {
        guard
            activeApprovalFollowUpGeneration == generation,
            !approvalFollowUpPrepareInFlight
        else {
            return
        }

        guard approvalFollowUpAttemptsRemaining > 0 else {
            completeApprovalFollowUpTimedOut(generation: generation)
            return
        }

        approvalFollowUpAttemptsRemaining -= 1
        approvalFollowUpPrepareInFlight = true
        helperClient.prepareForUse { [weak self] result in
            self?.handleApprovalFollowUp(result, generation: generation)
        }
    }

    private func handleApprovalFollowUp(
        _ result: ClosedLidHelperPreparationResult,
        generation: Int
    ) {
        guard activeApprovalFollowUpGeneration == generation else {
            return
        }

        approvalFollowUpPrepareInFlight = false
        switch result {
        case .ready:
            let duration = approvalFollowUpDuration
            cancelApprovalFollowUp(resetBudget: false)
            state = .starting
            logStore.append("closed-lid helper approval confirmed; starting requested session")
            startPreparedSession(duration: duration)
        case .requiresApproval:
            scheduleApprovalFollowUpRetry(generation: generation)
        case .notFound(let message), .failure(let message):
            cancelApprovalFollowUp()
            state = .error(message)
            logStore.append("closed-lid helper approval follow-up failed: \(message)")
        case .unsafeActiveSession(let message):
            cancelApprovalFollowUp()
            clearActiveSession()
            state = .stopFailed(message)
            logStore.append(
                "closed-lid helper approval follow-up could not confirm restore: \(message); \(AppText.ClosedLid.manualRecovery)"
            )
        }
    }

    private func scheduleApprovalFollowUpRetry(generation: Int) {
        guard activeApprovalFollowUpGeneration == generation else {
            return
        }

        guard approvalFollowUpAttemptsRemaining > 0 else {
            completeApprovalFollowUpTimedOut(generation: generation)
            return
        }

        approvalFollowUpTimer?.invalidate()
        let timer = Timer(timeInterval: approvalFollowUpRetryInterval, repeats: false) { [weak self] _ in
            self?.pollApprovalFollowUp(generation: generation)
        }
        timer.tolerance = min(0.25, approvalFollowUpRetryInterval / 4)
        RunLoop.main.add(timer, forMode: .common)
        approvalFollowUpTimer = timer
    }

    private func armApprovalFollowUpTimeout(generation: Int) {
        approvalFollowUpTimeoutTimer?.invalidate()
        let timer = Timer(timeInterval: approvalFollowUpPrepareTimeout, repeats: false) { [weak self] _ in
            self?.completeApprovalFollowUpTimedOut(generation: generation)
        }
        timer.tolerance = min(1, approvalFollowUpPrepareTimeout / 10)
        RunLoop.main.add(timer, forMode: .common)
        approvalFollowUpTimeoutTimer = timer
    }

    private func completeApprovalFollowUpTimedOut(generation: Int) {
        guard activeApprovalFollowUpGeneration == generation else {
            return
        }

        cancelApprovalFollowUp()
        state = .requiresApproval
        logStore.append("closed-lid helper approval follow-up stopped before approval was confirmed")
    }

    private func cancelApprovalFollowUp(resetBudget: Bool = true) {
        approvalFollowUpTimer?.invalidate()
        approvalFollowUpTimer = nil
        approvalFollowUpTimeoutTimer?.invalidate()
        approvalFollowUpTimeoutTimer = nil
        approvalFollowUpDuration = nil
        approvalFollowUpPrepareInFlight = false
        activeApprovalFollowUpGeneration = nil
        if resetBudget {
            approvalFollowUpAttemptsRemaining = 0
            approvalAlertShownForCurrentStart = false
        }
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

        if hasPendingApprovalFollowUpStart, activeToken == nil {
            cancelPendingApprovalFollowUpStart(reason: reason)
            return
        }

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

    private func cancelPendingApprovalFollowUpStart(reason: String) {
        isStopInFlight = true
        activeStopReason = reason
        cancelApprovalFollowUp()
        clearActiveSession()
        state = .stopping
        logStore.append("closed-lid pending approval follow-up canceled reason=\(reason)")
        DispatchQueue.main.async { [weak self] in
            self?.completeStop(success: true, message: nil)
        }
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

    private func showApprovalRequiredAlertIfNeeded() {
        guard !approvalAlertShownForCurrentStart else {
            return
        }

        approvalAlertShownForCurrentStart = true
        showApprovalRequiredAlert()
    }

    private func showStopFailureAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = AppText.ClosedLid.stopFailureTitle
        alert.informativeText = AppText.ClosedLid.stopFailureBody(message)
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - 合盖压暗 / 开盖恢复
    //
    // 仅在 keep-awake 会话持有 lease（系统被阻止睡眠）时生效；
    // 其余状态完全不监听、不动亮度。生命周期由 state 变化驱动，确保任何结束
    // 路径（Stop Now、超时、崩溃、退出）都会恢复亮度。

    /// 该状态是否持有一个活动的 keep-awake lease（系统正被阻止睡眠）。
    private func stateHoldsSession(_ state: ClosedLidKeepAwakeState) -> Bool {
        switch state {
        case .activeTimed, .activeIndefinite, .errorWithActiveSession:
            return true
        case .off, .starting, .stopping, .requiresApproval, .error, .stopFailed:
            return false
        }
    }

    /// state 进入/离开"持有会话"时，自动开始/结束合盖监听与压暗。
    private func reconcileLidDimming(from oldState: ClosedLidKeepAwakeState, to newState: ClosedLidKeepAwakeState) {
        let was = stateHoldsSession(oldState)
        let now = stateHoldsSession(newState)
        if !was, now {
            beginLidDimming()
        } else if was, !now {
            endLidDimming()
        }
    }

    /// 会话激活时开始监听合盖，并对齐当前状态（用户可能在启动前/启动时就已合盖）。
    /// `LidStateObserver.start()` 自身幂等，重复调用安全。
    private func beginLidDimming() {
        lidObserver.start()
        if lidObserver.isLidCurrentlyClosed() {
            dimForLidClosed()
        }
    }

    /// 停止监听并兜底恢复亮度（正常情况下开盖已恢复，此处覆盖"合盖中会话结束"等场景）。
    private func endLidDimming() {
        lidObserver.stop()
        restoreBrightnessIfDimmed()
    }

    private func handleLidStateChanged(closed: Bool) {
        guard stateHoldsSession(state) else {
            return
        }
        if closed {
            dimForLidClosed()
        } else {
            restoreBrightnessIfDimmed()
        }
    }

    private func dimForLidClosed() {
        guard savedBrightness == nil else {
            return // 已处于压暗状态，避免覆盖保存值
        }
        guard let current = brightnessController.currentInternalBrightness() else {
            logStore.append("closed-lid dim skipped: could not read built-in brightness")
            return
        }
        if brightnessController.setInternalBrightness(0) {
            savedBrightness = current
            logStore.append("closed-lid dimmed built-in display (was \(String(format: "%.2f", current)))")
        } else {
            logStore.append("closed-lid dim failed to set brightness")
        }
    }

    private func restoreBrightnessIfDimmed() {
        guard let saved = savedBrightness else {
            return
        }
        savedBrightness = nil
        let restored = max(saved, LidDimming.minimumRestoredBrightness)
        if brightnessController.setInternalBrightness(restored) {
            logStore.append("closed-lid restored built-in brightness to \(String(format: "%.2f", restored))")
        } else {
            logStore.append("closed-lid failed to restore brightness to \(String(format: "%.2f", restored))")
        }
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
