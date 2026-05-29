import DockTapClosedLidHelperCore
import XCTest

final class ClosedLidHelperCoreTests: XCTestCase {
    private let baseDate = Date(timeIntervalSinceReferenceDate: 1_000)

    func testPowerCommandsUseFixedPmsetArguments() {
        XCTAssertEqual(ClosedLidPowerCommand.enableKeepAwake.pmsetArguments, ["-a", "disablesleep", "1"])
        XCTAssertEqual(ClosedLidPowerCommand.restoreNormalSleep.pmsetArguments, ["-a", "disablesleep", "0"])
    }

    func testStartWritesPendingJournalBeforePmsetEnableAndMarksActiveAfterSuccess() {
        let harness = makeHarness(token: "token-1")
        let diagnostics = ClosedLidClientDiagnostics(processIdentifier: 123, effectiveUserIdentifier: 501)

        let result = harness.core.start(durationSeconds: 3_600, clientDiagnostics: diagnostics)

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.lease?.token, "token-1")
        XCTAssertEqual(result.lease?.mode, .timed)
        XCTAssertEqual(result.lease?.hardExpiryDate, baseDate.addingTimeInterval(3_600))
        XCTAssertEqual(result.lease?.leaseDeadlineDate, baseDate.addingTimeInterval(90))
        XCTAssertEqual(result.lease?.clientDiagnostics, diagnostics)
        XCTAssertEqual(harness.runner.commands, [.enableKeepAwake])
        XCTAssertEqual(harness.journal.entry?.phase, .active)
        XCTAssertEqual(harness.recorder.events, [
            "journal.savePendingEnable",
            "command.enableKeepAwake",
            "journal.markActive"
        ])
    }

    func testStartFailureRestoresNormalSleepAndClearsPendingJournal() {
        let harness = makeHarness()
        harness.runner.enqueue(.failure(status: 7, standardError: "denied"), for: .enableKeepAwake)

        let result = harness.core.start(durationSeconds: nil, clientDiagnostics: ClosedLidClientDiagnostics())

        XCTAssertEqual(result.outcome, .pmsetFailed)
        XCTAssertTrue(result.pmsetRestoreConfirmed)
        XCTAssertEqual(harness.runner.commands, [.enableKeepAwake, .restoreNormalSleep])
        XCTAssertNil(harness.journal.entry)
        XCTAssertEqual(harness.recorder.events, [
            "journal.savePendingEnable",
            "command.enableKeepAwake",
            "command.restoreNormalSleep",
            "journal.clear"
        ])
    }

    func testAlreadyActiveStartReturnsAlreadyActiveAndLeavesExistingLeaseAndJournalUnchanged() {
        let harness = makeHarness(token: "first-token")
        let first = harness.core.start(durationSeconds: 3_600, clientDiagnostics: ClosedLidClientDiagnostics())
        let firstEntry = harness.journal.entry
        let eventCount = harness.recorder.events.count

        harness.now = baseDate.addingTimeInterval(10)
        let second = harness.core.start(durationSeconds: nil, clientDiagnostics: ClosedLidClientDiagnostics())

        XCTAssertEqual(first.outcome, .success)
        XCTAssertEqual(second.outcome, .alreadyActive)
        XCTAssertEqual(second.lease, first.lease)
        XCTAssertEqual(harness.journal.entry, firstEntry)
        XCTAssertEqual(harness.runner.commands, [.enableKeepAwake])
        XCTAssertEqual(harness.recorder.events.count, eventCount)
    }

    func testStopNowRestoresNormalSleepAndClearsJournal() {
        let harness = makeHarness(token: "stop-token")
        let start = harness.core.start(durationSeconds: nil, clientDiagnostics: ClosedLidClientDiagnostics())

        let stop = harness.core.stop(token: start.lease?.token ?? "", reason: "menu")

        XCTAssertEqual(stop.outcome, .success)
        XCTAssertTrue(stop.pmsetRestoreConfirmed)
        XCTAssertEqual(harness.runner.commands, [.enableKeepAwake, .restoreNormalSleep])
        XCTAssertNil(harness.journal.entry)
        XCTAssertEqual(harness.core.status().state, .off)
    }

    func testLeaseDeadlineExpiryRestoresNormalSleepAndClearsJournal() {
        let harness = makeHarness()
        _ = harness.core.start(durationSeconds: nil, clientDiagnostics: ClosedLidClientDiagnostics())

        harness.now = baseDate.addingTimeInterval(91)
        let result = harness.core.enforceDeadlines()

        XCTAssertEqual(result.outcome, .expired)
        XCTAssertTrue(result.pmsetRestoreConfirmed)
        XCTAssertEqual(harness.runner.commands, [.enableKeepAwake, .restoreNormalSleep])
        XCTAssertNil(harness.journal.entry)
        XCTAssertEqual(harness.core.status().state, .off)
    }

    func testTimedExpiryWinsEvenAfterLeaseRenewalExtendsDeadline() {
        let harness = makeHarness(token: "timed-token")
        let start = harness.core.start(durationSeconds: 60, clientDiagnostics: ClosedLidClientDiagnostics())

        harness.now = baseDate.addingTimeInterval(30)
        let renewal = harness.core.renewLease(token: start.lease?.token ?? "")
        XCTAssertEqual(renewal.outcome, .success)
        XCTAssertEqual(renewal.lease?.leaseDeadlineDate, baseDate.addingTimeInterval(120))

        harness.now = baseDate.addingTimeInterval(61)
        let expiry = harness.core.enforceDeadlines()

        XCTAssertEqual(expiry.outcome, .expired)
        XCTAssertTrue(expiry.pmsetRestoreConfirmed)
        XCTAssertEqual(harness.runner.commands, [.enableKeepAwake, .restoreNormalSleep])
        XCTAssertNil(harness.journal.entry)
    }

    func testRecoverPendingJournalRestoresNormalSleepAndClearsJournal() {
        let lease = lease(token: "pending", mode: .indefinite, leaseDeadlineDate: baseDate.addingTimeInterval(90))
        let harness = makeHarness(initialJournal: ClosedLidJournalEntry(
            phase: .pendingEnable,
            lease: lease,
            updatedAtDate: baseDate
        ))

        let result = harness.core.recoverFromJournal()

        XCTAssertEqual(result.outcome, .success)
        XCTAssertTrue(result.pmsetRestoreConfirmed)
        XCTAssertEqual(harness.runner.commands, [.restoreNormalSleep])
        XCTAssertNil(harness.journal.entry)
    }

    func testRecoverValidActiveJournalResumesWithoutRunningPmset() {
        let lease = lease(token: "active", mode: .timed, leaseDeadlineDate: baseDate.addingTimeInterval(90))
        let harness = makeHarness(initialJournal: ClosedLidJournalEntry(
            phase: .active,
            lease: lease,
            updatedAtDate: baseDate
        ))

        let result = harness.core.recoverFromJournal()

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.lease, lease)
        XCTAssertTrue(harness.runner.commands.isEmpty)
        XCTAssertEqual(harness.core.status().state, .activeTimed)
    }

    func testRecoverStaleActiveJournalRestoresNormalSleepImmediately() {
        let lease = lease(token: "stale", mode: .indefinite, leaseDeadlineDate: baseDate.addingTimeInterval(-1))
        let harness = makeHarness(initialJournal: ClosedLidJournalEntry(
            phase: .active,
            lease: lease,
            updatedAtDate: baseDate.addingTimeInterval(-120)
        ))

        let result = harness.core.recoverFromJournal()

        XCTAssertEqual(result.outcome, .expired)
        XCTAssertTrue(result.pmsetRestoreConfirmed)
        XCTAssertEqual(harness.runner.commands, [.restoreNormalSleep])
        XCTAssertNil(harness.journal.entry)
    }

    func testRenewWithInvalidTokenDoesNotMutateJournal() {
        let harness = makeHarness(token: "valid-token")
        _ = harness.core.start(durationSeconds: nil, clientDiagnostics: ClosedLidClientDiagnostics())
        let activeEntry = harness.journal.entry

        harness.now = baseDate.addingTimeInterval(10)
        let renewal = harness.core.renewLease(token: "wrong-token")

        XCTAssertEqual(renewal.outcome, .invalidToken)
        XCTAssertEqual(harness.journal.entry, activeEntry)
        XCTAssertEqual(harness.runner.commands, [.enableKeepAwake])
    }

    private func makeHarness(
        token: String = "token",
        initialJournal: ClosedLidJournalEntry? = nil
    ) -> CoreHarness {
        CoreHarness(baseDate: baseDate, token: token, initialJournal: initialJournal)
    }

    private func lease(
        token: String,
        mode: ClosedLidLeaseMode,
        leaseDeadlineDate: Date
    ) -> ClosedLidActiveLease {
        ClosedLidActiveLease(
            token: token,
            mode: mode,
            startedAtDate: baseDate,
            hardExpiryDate: mode == .timed ? baseDate.addingTimeInterval(3_600) : nil,
            leaseDeadlineDate: leaseDeadlineDate,
            lastRenewalDate: baseDate,
            clientDiagnostics: ClosedLidClientDiagnostics(processIdentifier: 42, effectiveUserIdentifier: 501)
        )
    }
}

private final class CoreHarness {
    var now: Date {
        get { clock.now }
        set { clock.now = newValue }
    }

    private let clock: TestClock
    let recorder = EventRecorder()
    let runner: RecordingPowerCommandRunner
    let journal: RecordingJournalStore
    let core: ClosedLidHelperCore

    init(baseDate: Date, token: String, initialJournal: ClosedLidJournalEntry?) {
        clock = TestClock(now: baseDate)
        runner = RecordingPowerCommandRunner(recorder: recorder)
        journal = RecordingJournalStore(recorder: recorder, entry: initialJournal)
        let clock = clock
        core = ClosedLidHelperCore(
            commandRunner: runner,
            journalStore: journal,
            configuration: ClosedLidLeaseConfiguration(renewalInterval: 30, leaseTimeToLive: 90),
            currentDate: { clock.now },
            tokenGenerator: { token }
        )
    }
}

private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private final class EventRecorder {
    var events: [String] = []
}

private final class RecordingPowerCommandRunner: ClosedLidPowerCommandRunning {
    private let recorder: EventRecorder
    private var queuedResults: [ClosedLidPowerCommand: [ClosedLidPowerCommandResult]] = [:]
    private(set) var commands: [ClosedLidPowerCommand] = []

    init(recorder: EventRecorder) {
        self.recorder = recorder
    }

    func enqueue(_ result: ClosedLidPowerCommandResult, for command: ClosedLidPowerCommand) {
        queuedResults[command, default: []].append(result)
    }

    func run(_ command: ClosedLidPowerCommand) -> ClosedLidPowerCommandResult {
        recorder.events.append("command.\(command)")
        commands.append(command)

        guard var queue = queuedResults[command], !queue.isEmpty else {
            return ClosedLidPowerCommandResult(terminationStatus: 0)
        }

        let result = queue.removeFirst()
        queuedResults[command] = queue
        return result
    }
}

private final class RecordingJournalStore: ClosedLidJournalStoring {
    private let recorder: EventRecorder
    var entry: ClosedLidJournalEntry?

    init(recorder: EventRecorder, entry: ClosedLidJournalEntry?) {
        self.recorder = recorder
        self.entry = entry
    }

    func load() throws -> ClosedLidJournalEntry? {
        recorder.events.append("journal.load")
        return entry
    }

    func savePendingEnable(_ entry: ClosedLidJournalEntry) throws {
        recorder.events.append("journal.savePendingEnable")
        self.entry = entry
    }

    func markActive(_ entry: ClosedLidJournalEntry) throws {
        recorder.events.append("journal.markActive")
        self.entry = entry
    }

    func clear() throws {
        recorder.events.append("journal.clear")
        entry = nil
    }
}

private extension ClosedLidPowerCommandResult {
    static func failure(status: Int32, standardError: String = "") -> ClosedLidPowerCommandResult {
        ClosedLidPowerCommandResult(terminationStatus: status, standardError: standardError)
    }
}
