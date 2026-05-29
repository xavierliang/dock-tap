import DockTapClosedLidHelperCore
import DockTapClosedLidIPC
import Foundation

public final class ClosedLidHelperService: NSObject, ClosedLidHelperXPCProtocol {
    private let core: ClosedLidHelperCore
    private let logger: LaunchDaemonLogger
    private let queue = DispatchQueue(label: "ai.resopod.docktap.closedlidhelper.service")
    private var deadlineTimer: DispatchSourceTimer?

    public init(core: ClosedLidHelperCore, logger: LaunchDaemonLogger) {
        self.core = core
        self.logger = logger
        super.init()

        queue.sync {
            let recovery = core.recoverFromJournal()
            logRecovery(recovery)
            scheduleDeadlineTimer()
        }
    }

    public func start(durationSeconds: NSNumber?, completion: @escaping (ClosedLidStartReply) -> Void) {
        let diagnostics = Self.currentClientDiagnostics()
        let duration = durationSeconds?.doubleValue

        queue.async {
            let result = self.core.start(durationSeconds: duration, clientDiagnostics: diagnostics)
            self.log("start", result: result)
            self.scheduleDeadlineTimer()
            completion(Self.startReply(from: result))
        }
    }

    public func renewLease(tokenString: NSString, completion: @escaping (ClosedLidLeaseReply) -> Void) {
        let token = tokenString as String

        queue.async {
            let result = self.core.renewLease(token: token)
            self.log("renew", result: result)
            self.scheduleDeadlineTimer()
            completion(Self.leaseReply(from: result))
        }
    }

    public func stop(tokenString: NSString, reasonString: NSString, completion: @escaping (ClosedLidStopReply) -> Void) {
        let token = tokenString as String
        let reason = reasonString as String

        queue.async {
            let result = self.core.stop(token: token, reason: reason)
            self.log("stop reason=\(reason)", result: result)
            self.scheduleDeadlineTimer()
            completion(Self.stopReply(from: result))
        }
    }

    public func status(completion: @escaping (ClosedLidStatusReply) -> Void) {
        queue.async {
            let status = self.core.status()
            self.scheduleDeadlineTimer()
            completion(Self.statusReply(from: status))
        }
    }

    private func handleDeadlineTimer() {
        let result = core.enforceDeadlines()
        if result.outcome != .inactive {
            log("deadline", result: result)
        }
        scheduleDeadlineTimer()
    }

    private func scheduleDeadlineTimer() {
        deadlineTimer?.cancel()
        deadlineTimer = nil

        guard let deadlineDate = core.nextDeadlineDate() else {
            return
        }

        let interval = deadlineDate.timeIntervalSinceNow
        let delay = interval > 0 ? interval : 10
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.handleDeadlineTimer()
        }
        deadlineTimer = timer
        timer.resume()
    }

    private func logRecovery(_ result: ClosedLidCoreResult) {
        switch result.outcome {
        case .inactive:
            logger.info("journal recovery found no active lease")
        case .success where result.lease != nil:
            logger.info("journal recovery resumed token=\(result.lease?.token ?? "-")")
        case .success where result.pmsetRestoreConfirmed:
            logger.info("journal recovery restored normal sleep")
        default:
            log("journal recovery", result: result)
        }
    }

    private func log(_ operation: String, result: ClosedLidCoreResult) {
        let token = result.lease?.token ?? "-"
        let message = "\(operation) outcome=\(result.outcome.rawValue) token=\(token) restore=\(result.pmsetRestoreConfirmed) error=\(result.errorMessage ?? "-")"

        switch result.outcome {
        case .success, .inactive, .alreadyActive:
            logger.info(message)
        case .expired where result.pmsetRestoreConfirmed:
            logger.info(message)
        default:
            logger.error(message)
        }
    }

    private static func currentClientDiagnostics() -> ClosedLidClientDiagnostics {
        guard let connection = NSXPCConnection.current() else {
            return ClosedLidClientDiagnostics()
        }

        return ClosedLidClientDiagnostics(
            processIdentifier: connection.processIdentifier,
            effectiveUserIdentifier: connection.effectiveUserIdentifier
        )
    }

    private static func startReply(from result: ClosedLidCoreResult) -> ClosedLidStartReply {
        ClosedLidStartReply(
            outcome: outcomeString(for: result),
            tokenString: nsString(result.lease?.token),
            modeString: modeString(result.lease?.mode),
            hardExpiryDate: nsDate(result.lease?.hardExpiryDate),
            leaseDeadlineDate: nsDate(result.lease?.leaseDeadlineDate),
            lastRenewalDate: nsDate(result.lease?.lastRenewalDate),
            alreadyActive: NSNumber(value: result.outcome == .alreadyActive),
            errorMessage: nsString(result.errorMessage)
        )
    }

    private static func leaseReply(from result: ClosedLidCoreResult) -> ClosedLidLeaseReply {
        ClosedLidLeaseReply(
            outcome: outcomeString(for: result),
            tokenString: nsString(result.lease?.token),
            hardExpiryDate: nsDate(result.lease?.hardExpiryDate),
            leaseDeadlineDate: nsDate(result.lease?.leaseDeadlineDate),
            lastRenewalDate: nsDate(result.lease?.lastRenewalDate),
            errorMessage: nsString(result.errorMessage)
        )
    }

    private static func stopReply(from result: ClosedLidCoreResult) -> ClosedLidStopReply {
        ClosedLidStopReply(
            outcome: outcomeString(for: result),
            tokenString: nsString(result.lease?.token),
            stoppedAtDate: result.pmsetRestoreConfirmed ? result.occurredAtDate as NSDate : nil,
            pmsetRestoreConfirmed: NSNumber(value: result.pmsetRestoreConfirmed),
            errorMessage: nsString(result.errorMessage)
        )
    }

    private static func statusReply(from status: ClosedLidCoreStatus) -> ClosedLidStatusReply {
        ClosedLidStatusReply(
            stateString: statusString(for: status.state),
            tokenString: nsString(status.lease?.token),
            modeString: modeString(status.lease?.mode),
            hardExpiryDate: nsDate(status.lease?.hardExpiryDate),
            leaseDeadlineDate: nsDate(status.lease?.leaseDeadlineDate),
            lastRenewalDate: nsDate(status.lease?.lastRenewalDate),
            isActive: NSNumber(value: status.lease != nil),
            errorMessage: nsString(status.errorMessage)
        )
    }

    private static func outcomeString(for result: ClosedLidCoreResult) -> NSString {
        switch result.outcome {
        case .success:
            return ClosedLidResponseOutcome.success.rawValue as NSString
        case .alreadyActive:
            return ClosedLidResponseOutcome.alreadyActive.rawValue as NSString
        case .inactive:
            return ClosedLidResponseOutcome.inactive.rawValue as NSString
        case .invalidToken:
            return ClosedLidResponseOutcome.invalidToken.rawValue as NSString
        case .expired:
            return ClosedLidResponseOutcome.expired.rawValue as NSString
        case .pmsetFailed:
            return ClosedLidResponseOutcome.pmsetFailed.rawValue as NSString
        case .restoreFailed:
            return ClosedLidResponseOutcome.restoreFailed.rawValue as NSString
        case .journalFailed, .invalidRequest:
            return ClosedLidResponseOutcome.error.rawValue as NSString
        }
    }

    private static func statusString(for state: ClosedLidCoreStatusState) -> NSString {
        switch state {
        case .off:
            return ClosedLidStatusState.off.rawValue as NSString
        case .activeTimed:
            return ClosedLidStatusState.activeTimed.rawValue as NSString
        case .activeIndefinite:
            return ClosedLidStatusState.activeIndefinite.rawValue as NSString
        case .error:
            return ClosedLidStatusState.error.rawValue as NSString
        }
    }

    private static func modeString(_ mode: ClosedLidLeaseMode?) -> NSString? {
        guard let mode else {
            return nil
        }

        switch mode {
        case .timed:
            return ClosedLidSessionMode.timed.rawValue as NSString
        case .indefinite:
            return ClosedLidSessionMode.indefinite.rawValue as NSString
        }
    }

    private static func nsDate(_ date: Date?) -> NSDate? {
        date.map { $0 as NSDate }
    }

    private static func nsString(_ string: String?) -> NSString? {
        string.map { $0 as NSString }
    }
}
