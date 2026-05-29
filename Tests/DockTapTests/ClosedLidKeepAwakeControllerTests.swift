import AppKit
import ObjectiveC.runtime
import XCTest
@testable import DockTap

final class ClosedLidKeepAwakeControllerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settingsStore: SettingsStore!
    private var helperClient: FakeClosedLidHelperClient!
    private var logStore: LogStore!
    private var controller: ClosedLidKeepAwakeController!

    override class func setUp() {
        super.setUp()
        AlertRunModalStub.install()
    }

    override class func tearDown() {
        AlertRunModalStub.uninstall()
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        suiteName = "DockTapTests.ClosedLidKeepAwakeController.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        settingsStore = SettingsStore(defaults: defaults)
        helperClient = FakeClosedLidHelperClient()
        logStore = LogStore()
        controller = ClosedLidKeepAwakeController(
            settingsStore: settingsStore,
            helperClient: helperClient,
            logStore: logStore
        )
        AlertRunModalStub.reset()
    }

    override func tearDown() {
        controller.invalidate()
        defaults.removePersistentDomain(forName: suiteName)
        controller = nil
        logStore = nil
        helperClient = nil
        settingsStore = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFirstUseWarningContinueStoresAcknowledgementAndStartsTimedSession() {
        let endDate = Date(timeIntervalSinceReferenceDate: 9_000)
        helperClient.startResults.append(.started(.timed(token: "timed-token", endDate: endDate)))
        AlertRunModalStub.response = .alertFirstButtonReturn

        controller.enableForOneHour()

        XCTAssertTrue(settingsStore.hasSeenClosedLidWarning)
        XCTAssertEqual(helperClient.prepareCallCount, 1)
        XCTAssertEqual(helperClient.startDurations.count, 1)
        XCTAssertEqual(helperClient.startDurations[0], 3_600)
        XCTAssertEqual(AlertRunModalStub.alerts.map(\.messageText), [AppText.ClosedLid.warningTitle])
        XCTAssertTrue(AlertRunModalStub.alerts.first?.informativeText.contains("pmset disablesleep") == true)
        XCTAssertActiveTimed(endDate, controller.state)
    }

    func testFirstUseWarningCancelLeavesHelperAndPmsetUntouched() {
        AlertRunModalStub.response = .alertSecondButtonReturn

        controller.enableIndefinitely()

        XCTAssertFalse(settingsStore.hasSeenClosedLidWarning)
        XCTAssertEqual(helperClient.prepareCallCount, 0)
        XCTAssertTrue(helperClient.startDurations.isEmpty)
        XCTAssertEqual(controller.state, .off)
        XCTAssertEqual(AlertRunModalStub.alerts.map(\.messageText), [AppText.ClosedLid.warningTitle])
    }

    func testEnableIndefinitelyStartsNilDurationAndStopNowStopsToken() {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.startResults.append(.started(.indefinite(token: "forever-token")))

        controller.enableIndefinitely()
        controller.stopNow()

        XCTAssertEqual(helperClient.startDurations.count, 1)
        XCTAssertNil(helperClient.startDurations[0])
        XCTAssertEqual(helperClient.stopTokens, ["forever-token"])
        XCTAssertEqual(helperClient.stopReasons, ["menu"])
        XCTAssertEqual(controller.state, .off)
    }

    func testAlreadyActiveResultAdoptsHelperSessionAndSuppressesModeSwitching() {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.startResults.append(.alreadyActive(.indefinite(token: "existing-token")))

        controller.enableForOneHour()
        controller.enableIndefinitely()

        XCTAssertEqual(helperClient.startDurations.count, 1)
        XCTAssertEqual(helperClient.startDurations[0], 3_600)
        XCTAssertEqual(controller.state, .activeIndefinite)
    }

    func testStartFailureMovesToErrorStateWithoutActiveSession() {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.startResults.append(.failure("helper start failed"))

        controller.enableForOneHour()

        XCTAssertEqual(helperClient.startDurations.count, 1)
        XCTAssertEqual(controller.state, .error("helper start failed"))
    }

    func testStartFailureWithActiveLeaseStopsImmediately() {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.startResults.append(.failedWithActiveSession(
            .indefinite(token: "rollback-token"),
            "pmset disablesleep 1 succeeded but restore failed"
        ))

        controller.enableIndefinitely()

        XCTAssertEqual(helperClient.stopTokens, ["rollback-token"])
        XCTAssertEqual(helperClient.stopReasons, ["startFailure"])
        XCTAssertEqual(controller.state, .off)
    }

    func testHelperApprovalRequiredStateOffersLoginItemsSettings() {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.prepareResults = [.requiresApproval]
        AlertRunModalStub.response = .alertFirstButtonReturn

        controller.enableForOneHour()

        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertTrue(helperClient.startDurations.isEmpty)
        XCTAssertEqual(helperClient.openApprovalSettingsCallCount, 1)
        XCTAssertEqual(AlertRunModalStub.alerts.map(\.messageText), [AppText.ClosedLid.helperApprovalRequired])
    }

    func testApprovalFollowUpStartsRequestedSessionAfterHelperBecomesReady() {
        settingsStore.hasSeenClosedLidWarning = true
        let endDate = Date(timeIntervalSinceReferenceDate: 10_500)
        helperClient.prepareResults = [.requiresApproval, .ready]
        helperClient.startResults.append(.started(.timed(token: "approved-token", endDate: endDate)))
        AlertRunModalStub.response = .alertFirstButtonReturn

        controller.enableForOneHour()

        XCTAssertEqual(helperClient.prepareCallCount, 2)
        XCTAssertEqual(helperClient.startDurations.count, 1)
        XCTAssertEqual(helperClient.startDurations[0], 3_600)
        XCTAssertEqual(helperClient.openApprovalSettingsCallCount, 1)
        XCTAssertEqual(AlertRunModalStub.alerts.map(\.messageText), [AppText.ClosedLid.helperApprovalRequired])
        XCTAssertActiveTimed(endDate, controller.state)
    }

    func testApprovalFollowUpDoesNotRepeatApprovalAlertForSameEnableRequest() {
        settingsStore.hasSeenClosedLidWarning = true
        let endDate = Date(timeIntervalSinceReferenceDate: 11_500)
        helperClient.prepareResults = [.requiresApproval, .ready, .ready]
        helperClient.startResults.append(.requiresApproval)
        helperClient.startResults.append(.started(.timed(token: "approved-token", endDate: endDate)))
        AlertRunModalStub.response = .alertFirstButtonReturn

        controller.enableForOneHour()

        XCTAssertEqual(helperClient.prepareCallCount, 3)
        XCTAssertEqual(helperClient.startDurations.count, 2)
        XCTAssertEqual(helperClient.startDurations[0], 3_600)
        XCTAssertEqual(helperClient.startDurations[1], 3_600)
        XCTAssertEqual(helperClient.openApprovalSettingsCallCount, 1)
        XCTAssertEqual(AlertRunModalStub.alerts.map(\.messageText), [AppText.ClosedLid.helperApprovalRequired])
        XCTAssertActiveTimed(endDate, controller.state)
    }

    func testStopBeforeTerminationCancelsPendingApprovalFollowUpBeforeItCanStart() {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.prepareResults = [.requiresApproval]

        controller.enableForOneHour()
        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertTrue(controller.requiresStopGate)

        var completion: (success: Bool, message: String?)?
        controller.stopBeforeTermination(reason: "update") { success, message in
            completion = (success, message)
        }

        XCTAssertNil(completion)
        XCTAssertEqual(controller.state, .stopping)
        XCTAssertTrue(controller.requiresStopGate)

        runMainRunLoop(until: { completion != nil })

        XCTAssertEqual(completion?.success, true)
        XCTAssertNil(completion?.message)
        XCTAssertEqual(controller.state, .off)
        XCTAssertFalse(controller.requiresStopGate)

        helperClient.completePendingPrepare(.ready)

        XCTAssertTrue(helperClient.startDurations.isEmpty)
        XCTAssertTrue(helperClient.stopTokens.isEmpty)
    }

    func testStopBeforeTerminationCancelsApprovalFollowUpRetryTimerBeforeItCanStartHelper() {
        recreateController(approvalFollowUpRetryInterval: 0.01)
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.prepareResults = [.requiresApproval, .requiresApproval, .ready]
        helperClient.startResults.append(.started(.timed(token: "late-approved-token", endDate: Date())))

        controller.enableForOneHour()
        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertEqual(helperClient.prepareCallCount, 2)
        XCTAssertTrue(controller.requiresStopGate)
        XCTAssertTrue(helperClient.startDurations.isEmpty)

        var completion: (success: Bool, message: String?)?
        controller.stopBeforeTermination(reason: "update") { success, message in
            completion = (success, message)
        }

        XCTAssertNil(completion)
        XCTAssertEqual(controller.state, .stopping)

        runMainRunLoop(until: { completion != nil })
        XCTAssertEqual(completion?.success, true)
        XCTAssertNil(completion?.message)
        XCTAssertEqual(controller.state, .off)
        XCTAssertFalse(controller.requiresStopGate)

        let prepareCallCountAfterCancellation = helperClient.prepareCallCount
        let retryDeadline = Date(timeIntervalSinceNow: 0.05)
        runMainRunLoop(until: { Date() >= retryDeadline })

        XCTAssertEqual(helperClient.prepareCallCount, prepareCallCountAfterCancellation)
        XCTAssertTrue(helperClient.startDurations.isEmpty)
        XCTAssertTrue(helperClient.stopTokens.isEmpty)
    }

    func testApprovalFollowUpBudgetDoesNotResetAcrossStartRequiresApprovalCycles() {
        recreateController(approvalFollowUpMaxAttempts: 2)
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.prepareResults = [.ready, .ready, .ready]
        helperClient.startResults = [.requiresApproval, .requiresApproval, .requiresApproval]

        controller.enableForOneHour()

        XCTAssertEqual(helperClient.prepareCallCount, 3)
        XCTAssertEqual(helperClient.startDurations.count, 3)
        XCTAssertEqual(helperClient.startDurations[0], 3_600)
        XCTAssertEqual(helperClient.startDurations[1], 3_600)
        XCTAssertEqual(helperClient.startDurations[2], 3_600)
        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertFalse(controller.requiresStopGate)
        XCTAssertEqual(helperClient.openApprovalSettingsCallCount, 1)
        XCTAssertEqual(AlertRunModalStub.alerts.map(\.messageText), [AppText.ClosedLid.helperApprovalRequired])
    }

    func testApprovalFollowUpRequiresApprovalRetryExhaustionStopsPendingGate() {
        recreateController(approvalFollowUpMaxAttempts: 1)
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.prepareResults = [.requiresApproval, .requiresApproval]

        controller.enableForOneHour()

        XCTAssertEqual(helperClient.prepareCallCount, 2)
        XCTAssertTrue(helperClient.startDurations.isEmpty)
        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertFalse(controller.requiresStopGate)
        XCTAssertEqual(AlertRunModalStub.alerts.map(\.messageText), [AppText.ClosedLid.helperApprovalRequired])
    }

    func testApprovalFollowUpHungPrepareTimesOutAndCannotLaterStart() {
        recreateController(approvalFollowUpPrepareTimeout: 0.01)
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.prepareResults = [.requiresApproval]

        controller.enableForOneHour()
        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertTrue(controller.requiresStopGate)

        runMainRunLoop(until: { !controller.requiresStopGate })
        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertFalse(controller.requiresStopGate)

        helperClient.completePendingPrepare(.ready)

        XCTAssertTrue(helperClient.startDurations.isEmpty)
    }

    func testRefreshStatusMirrorsActiveAndInactiveHelperStates() {
        let endDate = Date(timeIntervalSinceReferenceDate: 10_000)
        helperClient.statusResults.append(.active(.timed(token: "status-token", endDate: endDate)))
        helperClient.statusResults.append(.inactive)

        controller.refreshStatus()
        XCTAssertActiveTimed(endDate, controller.state)

        controller.refreshStatus()
        XCTAssertEqual(controller.state, .off)
    }

    func testRefreshStatusReconcilesApprovalStateAfterHelperNoLongerRequiresApproval() {
        helperClient.statusResults.append(.requiresApproval)
        helperClient.statusResults.append(.inactive)

        controller.refreshStatus()
        XCTAssertEqual(controller.state, .requiresApproval)

        controller.refreshStatus()
        XCTAssertEqual(controller.state, .off)
    }

    func testRefreshStatusUnsafeActiveSessionShowsStopFailedManualRecoveryState() {
        let message = "helper re-registration blocked: could not verify old helper status"
        helperClient.statusResults.append(.unsafeActiveSession(message))

        controller.refreshStatus()

        XCTAssertEqual(controller.state, .stopFailed(message))
        XCTAssertTrue(controller.state.canStopFromMenu)
        XCTAssertTrue(logStore.entries.contains { $0.text.contains(AppText.ClosedLid.manualRecovery) })
    }

    func testStopBeforeTerminationAllowsQuitOnlyAfterHelperConfirmsRestore() {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.startResults.append(.started(.timed(token: "quit-token", endDate: Date())))
        controller.enableForOneHour()

        var completion: (success: Bool, message: String?)?
        controller.stopBeforeTermination(reason: "quit") { success, message in
            completion = (success, message)
        }

        XCTAssertEqual(helperClient.stopTokens, ["quit-token"])
        XCTAssertEqual(helperClient.stopReasons, ["quit"])
        XCTAssertEqual(completion?.success, true)
        XCTAssertNil(completion?.message)
        XCTAssertEqual(controller.state, .off)
    }

    func testStopBeforeTerminationFailureCancelsQuitAndShowsManualRecovery() {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.startResults.append(.started(.indefinite(token: "blocked-token")))
        helperClient.stopResults.append(.failure("restore failed"))
        controller.enableIndefinitely()

        var completion: (success: Bool, message: String?)?
        controller.stopBeforeTermination(reason: "quit") { success, message in
            completion = (success, message)
        }

        XCTAssertEqual(completion?.success, false)
        XCTAssertEqual(completion?.message, "restore failed")
        XCTAssertEqual(controller.state, .stopFailed("restore failed"))
        XCTAssertEqual(AlertRunModalStub.alerts.last?.messageText, AppText.ClosedLid.stopFailureTitle)
        XCTAssertTrue(AlertRunModalStub.alerts.last?.informativeText.contains("sudo pmset -a disablesleep 0") == true)
    }

    func testStopBeforeTerminationDuringStartDefersStopUntilStartReplyArrives() {
        settingsStore.hasSeenClosedLidWarning = true

        controller.enableForOneHour()
        XCTAssertEqual(controller.state, .starting)

        var completion: (success: Bool, message: String?)?
        controller.stopBeforeTermination(reason: "update") { success, message in
            completion = (success, message)
        }

        XCTAssertEqual(controller.state, .stopping)
        XCTAssertTrue(helperClient.stopTokens.isEmpty)

        helperClient.completePendingStart(.started(.timed(token: "late-token", endDate: Date())))

        XCTAssertEqual(helperClient.stopTokens, ["late-token"])
        XCTAssertEqual(helperClient.stopReasons, ["update"])
        XCTAssertEqual(completion?.success, true)
        XCTAssertNil(completion?.message)
        XCTAssertEqual(controller.state, .off)
    }

    func testStopBeforeTerminationDuringStartStopsLeaseFromFailedStartBeforeAllowingQuit() {
        settingsStore.hasSeenClosedLidWarning = true

        controller.enableForOneHour()

        var completion: (success: Bool, message: String?)?
        controller.stopBeforeTermination(reason: "update") { success, message in
            completion = (success, message)
        }

        helperClient.completePendingStart(.failedWithActiveSession(
            .indefinite(token: "rollback-token"),
            "pmset disablesleep 1 succeeded but restore failed"
        ))

        XCTAssertEqual(helperClient.stopTokens, ["rollback-token"])
        XCTAssertEqual(helperClient.stopReasons, ["update"])
        XCTAssertEqual(completion?.success, true)
        XCTAssertNil(completion?.message)
        XCTAssertEqual(controller.state, .off)
    }

    func testStopBeforeTerminationDuringStartCancelsWhenFailedStartLeaseCannotBeStopped() {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.stopResults.append(.failure("restore still failed"))

        controller.enableForOneHour()

        var completion: (success: Bool, message: String?)?
        controller.stopBeforeTermination(reason: "quit") { success, message in
            completion = (success, message)
        }

        helperClient.completePendingStart(.failedWithActiveSession(
            .indefinite(token: "rollback-token"),
            "pmset disablesleep 1 succeeded but restore failed"
        ))

        XCTAssertEqual(helperClient.stopTokens, ["rollback-token"])
        XCTAssertEqual(helperClient.stopReasons, ["quit"])
        XCTAssertEqual(completion?.success, false)
        XCTAssertEqual(completion?.message, "restore still failed")
        XCTAssertEqual(controller.state, .stopFailed("restore still failed"))
    }

    func testStopBeforeTerminationDuringPendingPrepareAllowsQuitWhenApprovalIsRequired() {
        assertDeferredStopDuringPendingPrepareCompletesSuccessfully(.requiresApproval)
    }

    func testStopBeforeTerminationDuringPendingPrepareAllowsQuitWhenHelperIsMissing() {
        assertDeferredStopDuringPendingPrepareCompletesSuccessfully(.notFound("helper missing"))
    }

    func testStopBeforeTerminationDuringPendingPrepareAllowsQuitWhenPreparationFails() {
        assertDeferredStopDuringPendingPrepareCompletesSuccessfully(.failure("registration failed"))
    }

    func testStopBeforeTerminationDuringPendingPrepareCancelsWhenRestoreIsRequired() {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.prepareResults = []
        let message = "old helper stop failed: restore failed"

        controller.enableForOneHour()

        var completion: (success: Bool, message: String?)?
        controller.stopBeforeTermination(reason: "update") { success, message in
            completion = (success, message)
        }

        helperClient.completePendingPrepare(.unsafeActiveSession(message))

        XCTAssertEqual(completion?.success, false)
        XCTAssertEqual(completion?.message, message)
        XCTAssertEqual(controller.state, .stopFailed(message))
        XCTAssertTrue(helperClient.startDurations.isEmpty)
        XCTAssertTrue(helperClient.stopTokens.isEmpty)
        XCTAssertEqual(AlertRunModalStub.alerts.last?.messageText, AppText.ClosedLid.stopFailureTitle)
        XCTAssertTrue(AlertRunModalStub.alerts.last?.informativeText.contains("sudo pmset -a disablesleep 0") == true)
        XCTAssertTrue(logStore.entries.contains { $0.text.contains("sudo pmset -a disablesleep 0") })
    }

    func testRenewalFailurePreservesStopNowToken() {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.startResults.append(.started(.indefinite(token: "renew-token")))
        helperClient.renewResults.append(.failure("xpc failed"))

        controller.enableIndefinitely()
        controller.renewLease()
        XCTAssertEqual(controller.state, .errorWithActiveSession("xpc failed"))
        controller.stopNow()

        XCTAssertEqual(controller.state, .off)
        XCTAssertEqual(helperClient.stopTokens, ["renew-token"])
        XCTAssertEqual(helperClient.stopReasons, ["menu"])
    }

    func testRefreshStatusErrorWithActiveLeasePreservesStopNowToken() {
        helperClient.statusResults.append(.failureWithActiveSession(
            .indefinite(token: "status-token"),
            "helper reports restore failed"
        ))

        controller.refreshStatus()
        controller.stopNow()

        XCTAssertEqual(controller.state, .off)
        XCTAssertEqual(helperClient.stopTokens, ["status-token"])
        XCTAssertEqual(helperClient.stopReasons, ["menu"])
    }

    private func assertDeferredStopDuringPendingPrepareCompletesSuccessfully(
        _ preparationResult: ClosedLidHelperPreparationResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        settingsStore.hasSeenClosedLidWarning = true
        helperClient.prepareResults = []

        controller.enableForOneHour()
        XCTAssertEqual(controller.state, .starting, file: file, line: line)

        var completion: (success: Bool, message: String?)?
        controller.stopBeforeTermination(reason: "update") { success, message in
            completion = (success, message)
        }

        XCTAssertEqual(controller.state, .stopping, file: file, line: line)
        helperClient.completePendingPrepare(preparationResult)

        XCTAssertEqual(completion?.success, true, file: file, line: line)
        XCTAssertNil(completion?.message, file: file, line: line)
        XCTAssertEqual(controller.state, .off, file: file, line: line)
        XCTAssertTrue(helperClient.startDurations.isEmpty, file: file, line: line)
        XCTAssertTrue(helperClient.stopTokens.isEmpty, file: file, line: line)
        XCTAssertTrue(AlertRunModalStub.alerts.isEmpty, file: file, line: line)
    }

    private func XCTAssertActiveTimed(
        _ expectedEndDate: Date,
        _ state: ClosedLidKeepAwakeState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .activeTimed(let actualEndDate) = state else {
            XCTFail("Expected active timed state, got \(state)", file: file, line: line)
            return
        }

        XCTAssertEqual(actualEndDate, expectedEndDate, file: file, line: line)
    }

    private func recreateController(
        approvalFollowUpMaxAttempts: Int = 60,
        approvalFollowUpRetryInterval: TimeInterval = 1,
        approvalFollowUpPrepareTimeout: TimeInterval = 60
    ) {
        controller.invalidate()
        controller = ClosedLidKeepAwakeController(
            settingsStore: settingsStore,
            helperClient: helperClient,
            logStore: logStore,
            approvalFollowUpMaxAttempts: approvalFollowUpMaxAttempts,
            approvalFollowUpRetryInterval: approvalFollowUpRetryInterval,
            approvalFollowUpPrepareTimeout: approvalFollowUpPrepareTimeout
        )
    }

    private func runMainRunLoop(
        until condition: () -> Bool,
        timeout: TimeInterval = 0.5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

private final class FakeClosedLidHelperClient: ClosedLidHelperClienting {
    var prepareResults: [ClosedLidHelperPreparationResult] = [.ready]
    var startResults: [ClosedLidHelperStartResult] = []
    var renewResults: [ClosedLidHelperRenewResult] = []
    var stopResults: [ClosedLidHelperStopResult] = []
    var statusResults: [ClosedLidHelperStatusResult] = []

    private(set) var prepareCallCount = 0
    private(set) var startDurations: [TimeInterval?] = []
    private(set) var stopTokens: [String?] = []
    private(set) var stopReasons: [String] = []
    private(set) var openApprovalSettingsCallCount = 0
    private var pendingPrepareCompletion: ((ClosedLidHelperPreparationResult) -> Void)?
    private var pendingStartCompletion: ((ClosedLidHelperStartResult) -> Void)?

    func prepareForUse(completion: @escaping (ClosedLidHelperPreparationResult) -> Void) {
        prepareCallCount += 1
        if prepareResults.isEmpty {
            pendingPrepareCompletion = completion
        } else {
            completion(prepareResults.removeFirst())
        }
    }

    func completePendingPrepare(_ result: ClosedLidHelperPreparationResult) {
        let completion = pendingPrepareCompletion
        pendingPrepareCompletion = nil
        completion?(result)
    }

    func start(duration: TimeInterval?, completion: @escaping (ClosedLidHelperStartResult) -> Void) {
        startDurations.append(duration)
        if startResults.isEmpty {
            pendingStartCompletion = completion
        } else {
            completion(startResults.removeFirst())
        }
    }

    func completePendingStart(_ result: ClosedLidHelperStartResult) {
        let completion = pendingStartCompletion
        pendingStartCompletion = nil
        completion?(result)
    }

    func renewLease(token: String, completion: @escaping (ClosedLidHelperRenewResult) -> Void) {
        completion(renewResults.isEmpty ? .renewed : renewResults.removeFirst())
    }

    func stop(token: String?, reason: String, completion: @escaping (ClosedLidHelperStopResult) -> Void) {
        stopTokens.append(token)
        stopReasons.append(reason)
        completion(stopResults.isEmpty ? .stopped : stopResults.removeFirst())
    }

    func status(completion: @escaping (ClosedLidHelperStatusResult) -> Void) {
        completion(statusResults.isEmpty ? .inactive : statusResults.removeFirst())
    }

    func openApprovalSettings() {
        openApprovalSettingsCallCount += 1
    }

    func invalidate() {}
}

private extension ClosedLidHelperSession {
    static func timed(token: String, endDate: Date) -> ClosedLidHelperSession {
        ClosedLidHelperSession(token: token, mode: .timed, endDate: endDate)
    }

    static func indefinite(token: String) -> ClosedLidHelperSession {
        ClosedLidHelperSession(token: token, mode: .indefinite, endDate: nil)
    }
}

private enum AlertRunModalStub {
    struct CapturedAlert {
        let messageText: String
        let informativeText: String
    }

    static var response: NSApplication.ModalResponse = .alertFirstButtonReturn
    private(set) static var alerts: [CapturedAlert] = []
    private static var isInstalled = false

    static func install() {
        guard !isInstalled else {
            return
        }

        guard
            let original = class_getInstanceMethod(NSAlert.self, #selector(NSAlert.runModal)),
            let replacement = class_getInstanceMethod(NSAlert.self, #selector(NSAlert.dockTapTests_runModal))
        else {
            XCTFail("Could not install NSAlert runModal stub")
            return
        }

        method_exchangeImplementations(original, replacement)
        isInstalled = true
    }

    static func uninstall() {
        guard isInstalled else {
            return
        }

        guard
            let original = class_getInstanceMethod(NSAlert.self, #selector(NSAlert.runModal)),
            let replacement = class_getInstanceMethod(NSAlert.self, #selector(NSAlert.dockTapTests_runModal))
        else {
            return
        }

        method_exchangeImplementations(original, replacement)
        isInstalled = false
    }

    static func reset() {
        response = .alertFirstButtonReturn
        alerts = []
    }

    fileprivate static func capture(_ alert: NSAlert) -> NSApplication.ModalResponse {
        alerts.append(CapturedAlert(
            messageText: alert.messageText,
            informativeText: alert.informativeText
        ))
        return response
    }
}

private extension NSAlert {
    @objc func dockTapTests_runModal() -> NSApplication.ModalResponse {
        AlertRunModalStub.capture(self)
    }
}
