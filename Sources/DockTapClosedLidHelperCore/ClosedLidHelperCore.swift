import Foundation

public enum ClosedLidPowerCommand: Equatable, Sendable {
    case enableKeepAwake
    case restoreNormalSleep

    public var pmsetArguments: [String] {
        switch self {
        case .enableKeepAwake:
            return ["-a", "disablesleep", "1"]
        case .restoreNormalSleep:
            return ["-a", "disablesleep", "0"]
        }
    }
}

public struct ClosedLidPowerCommandResult: Equatable, Sendable {
    public let terminationStatus: Int32
    public let standardOutput: String
    public let standardError: String

    public init(terminationStatus: Int32, standardOutput: String = "", standardError: String = "") {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool {
        terminationStatus == 0
    }
}

public protocol ClosedLidPowerCommandRunning {
    func run(_ command: ClosedLidPowerCommand) -> ClosedLidPowerCommandResult
}

public struct ClosedLidLeaseConfiguration: Equatable, Sendable {
    public let renewalInterval: TimeInterval
    public let leaseTimeToLive: TimeInterval

    public init(renewalInterval: TimeInterval = 30, leaseTimeToLive: TimeInterval = 90) {
        self.renewalInterval = renewalInterval
        self.leaseTimeToLive = leaseTimeToLive
    }

    public static let standard = ClosedLidLeaseConfiguration()
}

public struct ClosedLidClientDiagnostics: Codable, Equatable, Sendable {
    public let processIdentifier: Int32?
    public let effectiveUserIdentifier: UInt32?

    public init(processIdentifier: Int32? = nil, effectiveUserIdentifier: UInt32? = nil) {
        self.processIdentifier = processIdentifier
        self.effectiveUserIdentifier = effectiveUserIdentifier
    }
}

public enum ClosedLidLeaseMode: String, Codable, Equatable, Sendable {
    case timed
    case indefinite
}

public struct ClosedLidActiveLease: Codable, Equatable, Sendable {
    public let token: String
    public let mode: ClosedLidLeaseMode
    public let startedAtDate: Date
    public let hardExpiryDate: Date?
    public let leaseDeadlineDate: Date
    public let lastRenewalDate: Date
    public let clientDiagnostics: ClosedLidClientDiagnostics

    public init(
        token: String,
        mode: ClosedLidLeaseMode,
        startedAtDate: Date,
        hardExpiryDate: Date?,
        leaseDeadlineDate: Date,
        lastRenewalDate: Date,
        clientDiagnostics: ClosedLidClientDiagnostics
    ) {
        self.token = token
        self.mode = mode
        self.startedAtDate = startedAtDate
        self.hardExpiryDate = hardExpiryDate
        self.leaseDeadlineDate = leaseDeadlineDate
        self.lastRenewalDate = lastRenewalDate
        self.clientDiagnostics = clientDiagnostics
    }

    public func renewed(at date: Date, leaseTimeToLive: TimeInterval) -> ClosedLidActiveLease {
        ClosedLidActiveLease(
            token: token,
            mode: mode,
            startedAtDate: startedAtDate,
            hardExpiryDate: hardExpiryDate,
            leaseDeadlineDate: date.addingTimeInterval(leaseTimeToLive),
            lastRenewalDate: date,
            clientDiagnostics: clientDiagnostics
        )
    }
}

public enum ClosedLidJournalPhase: String, Codable, Equatable, Sendable {
    case pendingEnable
    case active
}

public struct ClosedLidJournalEntry: Codable, Equatable, Sendable {
    public let phase: ClosedLidJournalPhase
    public let lease: ClosedLidActiveLease
    public let updatedAtDate: Date

    public init(phase: ClosedLidJournalPhase, lease: ClosedLidActiveLease, updatedAtDate: Date) {
        self.phase = phase
        self.lease = lease
        self.updatedAtDate = updatedAtDate
    }

    public func withPhase(_ phase: ClosedLidJournalPhase, updatedAtDate: Date) -> ClosedLidJournalEntry {
        ClosedLidJournalEntry(phase: phase, lease: lease, updatedAtDate: updatedAtDate)
    }

    public func withLease(_ lease: ClosedLidActiveLease, updatedAtDate: Date) -> ClosedLidJournalEntry {
        ClosedLidJournalEntry(phase: phase, lease: lease, updatedAtDate: updatedAtDate)
    }
}

public protocol ClosedLidJournalStoring {
    func load() throws -> ClosedLidJournalEntry?
    func savePendingEnable(_ entry: ClosedLidJournalEntry) throws
    func markActive(_ entry: ClosedLidJournalEntry) throws
    func clear() throws
}

public enum ClosedLidCoreOutcome: String, Equatable, Sendable {
    case success
    case alreadyActive
    case inactive
    case invalidToken
    case expired
    case pmsetFailed
    case restoreFailed
    case journalFailed
    case invalidRequest
}

public struct ClosedLidCoreResult: Equatable, Sendable {
    public let outcome: ClosedLidCoreOutcome
    public let lease: ClosedLidActiveLease?
    public let pmsetRestoreConfirmed: Bool
    public let occurredAtDate: Date
    public let errorMessage: String?

    public init(
        outcome: ClosedLidCoreOutcome,
        lease: ClosedLidActiveLease? = nil,
        pmsetRestoreConfirmed: Bool = false,
        occurredAtDate: Date,
        errorMessage: String? = nil
    ) {
        self.outcome = outcome
        self.lease = lease
        self.pmsetRestoreConfirmed = pmsetRestoreConfirmed
        self.occurredAtDate = occurredAtDate
        self.errorMessage = errorMessage
    }
}

public enum ClosedLidCoreStatusState: String, Equatable, Sendable {
    case off
    case activeTimed
    case activeIndefinite
    case error
}

public struct ClosedLidCoreStatus: Equatable, Sendable {
    public let state: ClosedLidCoreStatusState
    public let lease: ClosedLidActiveLease?
    public let errorMessage: String?

    public init(state: ClosedLidCoreStatusState, lease: ClosedLidActiveLease? = nil, errorMessage: String? = nil) {
        self.state = state
        self.lease = lease
        self.errorMessage = errorMessage
    }
}

public final class ClosedLidHelperCore {
    public typealias CurrentDateProvider = () -> Date
    public typealias TokenGenerator = () -> String

    private let commandRunner: ClosedLidPowerCommandRunning
    private let journalStore: ClosedLidJournalStoring
    private let configuration: ClosedLidLeaseConfiguration
    private let currentDate: CurrentDateProvider
    private let tokenGenerator: TokenGenerator

    private var activeLease: ClosedLidActiveLease?
    private var lastErrorMessage: String?

    public init(
        commandRunner: ClosedLidPowerCommandRunning,
        journalStore: ClosedLidJournalStoring,
        configuration: ClosedLidLeaseConfiguration = .standard,
        currentDate: @escaping CurrentDateProvider = Date.init,
        tokenGenerator: @escaping TokenGenerator = { UUID().uuidString }
    ) {
        self.commandRunner = commandRunner
        self.journalStore = journalStore
        self.configuration = configuration
        self.currentDate = currentDate
        self.tokenGenerator = tokenGenerator
    }

    public func recoverFromJournal() -> ClosedLidCoreResult {
        let date = currentDate()

        do {
            guard let entry = try journalStore.load() else {
                activeLease = nil
                lastErrorMessage = nil
                return result(.inactive, at: date)
            }

            switch entry.phase {
            case .pendingEnable:
                activeLease = entry.lease
                return restoreNormalSleepAndClearJournal(
                    outcome: .success,
                    lease: entry.lease,
                    at: date,
                    clearFailureMessagePrefix: "Recovered pending enable journal but could not clear it"
                )
            case .active:
                guard isValidForResume(entry.lease, at: date) else {
                    activeLease = entry.lease
                    return restoreNormalSleepAndClearJournal(
                        outcome: .expired,
                        lease: entry.lease,
                        at: date,
                        clearFailureMessagePrefix: "Recovered stale active journal but could not clear it"
                    )
                }

                activeLease = entry.lease
                lastErrorMessage = nil
                return result(.success, lease: entry.lease, at: date)
            }
        } catch {
            activeLease = nil
            let restore = commandRunner.run(.restoreNormalSleep)
            if restore.succeeded {
                try? journalStore.clear()
                lastErrorMessage = nil
                return result(.success, pmsetRestoreConfirmed: true, at: date)
            }
            let message = "Could not read journal and restore normal sleep: \(commandFailureMessage(restore, fallback: error.localizedDescription))"
            lastErrorMessage = message
            return result(.restoreFailed, at: date, errorMessage: message)
        }
    }

    public func start(durationSeconds: TimeInterval?, clientDiagnostics: ClosedLidClientDiagnostics) -> ClosedLidCoreResult {
        let date = currentDate()

        let deadlineResult = enforceDeadlines(at: date)
        if deadlineResult.outcome == .restoreFailed || deadlineResult.outcome == .journalFailed {
            return deadlineResult
        }

        if let activeLease {
            return result(.alreadyActive, lease: activeLease, at: date)
        }

        if let durationSeconds, durationSeconds <= 0 {
            return result(.invalidRequest, at: date, errorMessage: "Duration must be positive")
        }

        let mode: ClosedLidLeaseMode = durationSeconds == nil ? .indefinite : .timed
        let hardExpiryDate = durationSeconds.map { date.addingTimeInterval($0) }
        let lease = ClosedLidActiveLease(
            token: tokenGenerator(),
            mode: mode,
            startedAtDate: date,
            hardExpiryDate: hardExpiryDate,
            leaseDeadlineDate: date.addingTimeInterval(configuration.leaseTimeToLive),
            lastRenewalDate: date,
            clientDiagnostics: clientDiagnostics
        )
        let pendingEntry = ClosedLidJournalEntry(phase: .pendingEnable, lease: lease, updatedAtDate: date)

        do {
            try journalStore.savePendingEnable(pendingEntry)
        } catch {
            let message = "Could not write pending keep-awake journal before pmset: \(error.localizedDescription)"
            lastErrorMessage = message
            return result(.journalFailed, lease: lease, at: date, errorMessage: message)
        }

        let enableResult = commandRunner.run(.enableKeepAwake)
        guard enableResult.succeeded else {
            let restore = commandRunner.run(.restoreNormalSleep)
            try? journalStore.clear()
            activeLease = nil
            let message = "pmset disablesleep 1 failed: \(commandFailureMessage(enableResult)); restore attempted: \(restore.succeeded)"
            lastErrorMessage = message
            return result(.pmsetFailed, lease: lease, pmsetRestoreConfirmed: restore.succeeded, at: date, errorMessage: message)
        }

        let activeEntry = pendingEntry.withPhase(.active, updatedAtDate: currentDate())
        do {
            try journalStore.markActive(activeEntry)
        } catch {
            activeLease = lease
            let restore = commandRunner.run(.restoreNormalSleep)
            if restore.succeeded {
                activeLease = nil
                try? journalStore.clear()
            }
            let message = "pmset disablesleep 1 succeeded but active journal mark failed: \(error.localizedDescription)"
            lastErrorMessage = message
            return result(
                restore.succeeded ? .journalFailed : .restoreFailed,
                lease: restore.succeeded ? nil : lease,
                pmsetRestoreConfirmed: restore.succeeded,
                at: date,
                errorMessage: message
            )
        }

        activeLease = activeEntry.lease
        lastErrorMessage = nil
        return result(.success, lease: activeEntry.lease, at: date)
    }

    public func renewLease(token: String) -> ClosedLidCoreResult {
        let date = currentDate()
        let deadlineResult = enforceDeadlines(at: date)
        if deadlineResult.outcome == .restoreFailed || deadlineResult.outcome == .journalFailed || deadlineResult.outcome == .expired {
            return deadlineResult
        }

        guard let lease = activeLease else {
            return result(.inactive, at: date)
        }
        guard lease.token == token else {
            return result(.invalidToken, lease: lease, at: date)
        }

        let renewedLease = lease.renewed(at: date, leaseTimeToLive: configuration.leaseTimeToLive)
        let activeEntry = ClosedLidJournalEntry(phase: .active, lease: renewedLease, updatedAtDate: date)

        do {
            try journalStore.markActive(activeEntry)
        } catch {
            let message = "Could not persist renewed lease: \(error.localizedDescription)"
            lastErrorMessage = message
            return result(.journalFailed, lease: lease, at: date, errorMessage: message)
        }

        activeLease = renewedLease
        lastErrorMessage = nil
        return result(.success, lease: renewedLease, at: date)
    }

    public func stop(token: String, reason: String) -> ClosedLidCoreResult {
        let date = currentDate()

        guard let lease = activeLease else {
            return restoreNormalSleepAndClearJournal(
                outcome: .inactive,
                lease: nil,
                at: date,
                clearFailureMessagePrefix: "Normal sleep restored but inactive journal cleanup failed"
            )
        }
        guard lease.token == token else {
            return result(.invalidToken, lease: lease, at: date)
        }

        return restoreNormalSleepAndClearJournal(
            outcome: .success,
            lease: lease,
            at: date,
            clearFailureMessagePrefix: "Stop Now restored normal sleep but could not clear journal"
        )
    }

    @discardableResult
    public func enforceDeadlines() -> ClosedLidCoreResult {
        enforceDeadlines(at: currentDate())
    }

    public func status() -> ClosedLidCoreStatus {
        _ = enforceDeadlines(at: currentDate())

        if let lease = activeLease {
            if let lastErrorMessage {
                return ClosedLidCoreStatus(state: .error, lease: lease, errorMessage: lastErrorMessage)
            }

            switch lease.mode {
            case .timed:
                return ClosedLidCoreStatus(state: .activeTimed, lease: lease)
            case .indefinite:
                return ClosedLidCoreStatus(state: .activeIndefinite, lease: lease)
            }
        }

        if let lastErrorMessage {
            return ClosedLidCoreStatus(state: .error, errorMessage: lastErrorMessage)
        }

        return ClosedLidCoreStatus(state: .off)
    }

    public func nextDeadlineDate() -> Date? {
        guard let lease = activeLease else {
            return nil
        }

        if let hardExpiryDate = lease.hardExpiryDate {
            return min(hardExpiryDate, lease.leaseDeadlineDate)
        }

        return lease.leaseDeadlineDate
    }

    private func enforceDeadlines(at date: Date) -> ClosedLidCoreResult {
        guard let lease = activeLease else {
            return result(.inactive, at: date)
        }

        if let hardExpiryDate = lease.hardExpiryDate, hardExpiryDate <= date {
            return restoreNormalSleepAndClearJournal(
                outcome: .expired,
                lease: lease,
                at: date,
                clearFailureMessagePrefix: "Timed keep-awake expired and restored normal sleep but could not clear journal"
            )
        }

        if lease.leaseDeadlineDate <= date {
            return restoreNormalSleepAndClearJournal(
                outcome: .expired,
                lease: lease,
                at: date,
                clearFailureMessagePrefix: "Keep-awake lease expired and restored normal sleep but could not clear journal"
            )
        }

        return result(.success, lease: lease, at: date)
    }

    private func isValidForResume(_ lease: ClosedLidActiveLease, at date: Date) -> Bool {
        guard !lease.token.isEmpty else {
            return false
        }

        if let hardExpiryDate = lease.hardExpiryDate, hardExpiryDate <= date {
            return false
        }

        return lease.leaseDeadlineDate > date
    }

    private func restoreNormalSleepAndClearJournal(
        outcome: ClosedLidCoreOutcome,
        lease: ClosedLidActiveLease?,
        at date: Date,
        clearFailureMessagePrefix: String
    ) -> ClosedLidCoreResult {
        let restore = commandRunner.run(.restoreNormalSleep)
        guard restore.succeeded else {
            let message = "pmset disablesleep 0 failed: \(commandFailureMessage(restore))"
            lastErrorMessage = message
            activeLease = lease
            return result(.restoreFailed, lease: lease, at: date, errorMessage: message)
        }

        do {
            try journalStore.clear()
        } catch {
            let message = "\(clearFailureMessagePrefix): \(error.localizedDescription)"
            lastErrorMessage = message
            activeLease = nil
            return result(.journalFailed, pmsetRestoreConfirmed: true, at: date, errorMessage: message)
        }

        activeLease = nil
        lastErrorMessage = nil
        return result(outcome, pmsetRestoreConfirmed: true, at: date)
    }

    private func result(
        _ outcome: ClosedLidCoreOutcome,
        lease: ClosedLidActiveLease? = nil,
        pmsetRestoreConfirmed: Bool = false,
        at date: Date,
        errorMessage: String? = nil
    ) -> ClosedLidCoreResult {
        ClosedLidCoreResult(
            outcome: outcome,
            lease: lease,
            pmsetRestoreConfirmed: pmsetRestoreConfirmed,
            occurredAtDate: date,
            errorMessage: errorMessage
        )
    }

    private func commandFailureMessage(_ result: ClosedLidPowerCommandResult, fallback: String? = nil) -> String {
        if !result.standardError.isEmpty {
            return "exit \(result.terminationStatus): \(result.standardError)"
        }
        if !result.standardOutput.isEmpty {
            return "exit \(result.terminationStatus): \(result.standardOutput)"
        }
        if let fallback, !fallback.isEmpty {
            return "exit \(result.terminationStatus): \(fallback)"
        }
        return "exit \(result.terminationStatus)"
    }
}
