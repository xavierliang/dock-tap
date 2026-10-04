import IOKit.pwr_mgt
import XCTest
@testable import DockTap

final class DisplayKeepAwakeControllerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var settings: SettingsStore!
    private var assertion: FakeDisplaySleepAssertion!
    private var controller: DisplayKeepAwakeController!

    override func setUp() {
        super.setUp()
        suite = "DockTapTests.DisplayKeepAwake.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        settings = SettingsStore(defaults: defaults)
        assertion = FakeDisplaySleepAssertion()
        controller = DisplayKeepAwakeController(settingsStore: settings, logStore: LogStore(), assertion: assertion)
    }

    override func tearDown() {
        controller = nil
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaultIsOffEvenDuringActiveSession() {
        controller.updateSessionState(.activeIndefinite)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.isHoldingAssertion)
        XCTAssertEqual(assertion.acquires, 0)
    }

    func testPreferenceAloneDoesNotHoldDisplayAwakeBeforeSessionStarts() {
        controller.setEnabled(true)
        controller.updateSessionState(.starting)
        controller.updateSessionState(.requiresApproval)
        XCTAssertEqual(assertion.acquires, 0)
        XCTAssertTrue(SettingsStore(defaults: defaults).keepDisplayAwakeDuringSession)
        controller.updateSessionState(.activeIndefinite)
        XCTAssertEqual(assertion.acquires, 1)
        XCTAssertTrue(controller.isHoldingAssertion)
    }

    func testEnablingAndDisablingMidSessionAcquiresAndReleases() {
        controller.updateSessionState(.activeIndefinite)
        controller.setEnabled(true)
        XCTAssertEqual(assertion.acquires, 1)
        controller.setEnabled(false)
        XCTAssertEqual(assertion.releases, [42])
        XCTAssertFalse(controller.isHoldingAssertion)
        XCTAssertFalse(SettingsStore(defaults: defaults).keepDisplayAwakeDuringSession)
    }

    func testRepeatedRefreshDoesNotDuplicateAssertions() {
        controller.setEnabled(true)
        controller.updateSessionState(.activeIndefinite)
        controller.updateSessionState(.activeIndefinite)
        controller.setEnabled(true)
        controller.reconcile()
        XCTAssertEqual(assertion.acquires, 1)
        controller.updateSessionState(.off)
        controller.updateSessionState(.off)
        XCTAssertEqual(assertion.releases, [42])
    }

    func testTimedExpiryReleasesButRemembersPreferenceForNextSession() {
        controller.setEnabled(true)
        controller.updateSessionState(.activeTimed(endDate: Date().addingTimeInterval(3600)))
        controller.updateSessionState(.off)
        XCTAssertEqual(assertion.releases, [42])
        XCTAssertTrue(controller.isEnabled)
        controller.updateSessionState(.activeIndefinite)
        XCTAssertEqual(assertion.acquires, 2)
    }

    func testStopFailurePreservesAssertionUntilHelperConfirmsOff() {
        controller.setEnabled(true)
        controller.updateSessionState(.activeIndefinite)
        controller.updateSessionState(.stopping)
        controller.updateSessionState(.stopFailed("helper unavailable"))
        XCTAssertTrue(controller.isHoldingAssertion)
        XCTAssertTrue(assertion.releases.isEmpty)
        controller.updateSessionState(.off)
        XCTAssertEqual(assertion.releases, [42])
    }

    func testActiveErrorKeepsAssertionButInactiveErrorReleasesIt() {
        controller.setEnabled(true)
        controller.updateSessionState(.errorWithActiveSession("retrying"))
        XCTAssertTrue(controller.isHoldingAssertion)
        controller.updateSessionState(.error("session ended"))
        XCTAssertEqual(assertion.releases, [42])
        XCTAssertFalse(controller.isHoldingAssertion)
    }

    func testFailedAcquireIsVisibleAndRetryCanRecover() {
        assertion.failAcquire = true
        controller.setEnabled(true)
        controller.updateSessionState(.activeIndefinite)
        XCTAssertFalse(controller.isHoldingAssertion)
        XCTAssertEqual(controller.errorMessage, AppText.DisplayKeepAwake.startFailed)
        assertion.failAcquire = false
        controller.reconcile()
        XCTAssertTrue(controller.isHoldingAssertion)
        XCTAssertNil(controller.errorMessage)
    }

    func testFailedReleaseRetainsIDForRetryInsteadOfLeakingAssertion() {
        controller.setEnabled(true)
        controller.updateSessionState(.activeIndefinite)
        assertion.failRelease = true
        controller.setEnabled(false)
        XCTAssertTrue(controller.isHoldingAssertion)
        XCTAssertEqual(controller.errorMessage, AppText.DisplayKeepAwake.stopFailed)
        assertion.failRelease = false
        controller.reconcile()
        XCTAssertEqual(assertion.releases, [42, 42])
        XCTAssertFalse(controller.isHoldingAssertion)
        XCTAssertNil(controller.errorMessage)
    }

    func testInvalidationReleasesOnceAndDoesNotErasePreference() {
        controller.setEnabled(true)
        controller.updateSessionState(.activeIndefinite)
        controller.invalidate()
        controller.invalidate()
        XCTAssertEqual(assertion.releases, [42])
        XCTAssertTrue(controller.isEnabled)
    }

    func testDeinitReleasesRemainingAssertion() {
        controller.setEnabled(true)
        controller.updateSessionState(.activeIndefinite)
        controller = nil
        XCTAssertEqual(assertion.releases, [42])
    }
}

private final class FakeDisplaySleepAssertion: DisplaySleepAsserting {
    var acquires = 0
    var releases: [IOPMAssertionID] = []
    var failAcquire = false
    var failRelease = false
    func acquire() -> IOPMAssertionID? {
        acquires += 1
        return failAcquire ? nil : 42
    }
    func release(_ id: IOPMAssertionID) -> Bool {
        releases.append(id)
        return !failRelease
    }
}
