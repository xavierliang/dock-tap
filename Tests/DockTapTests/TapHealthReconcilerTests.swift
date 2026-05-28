import XCTest
@testable import DockTap

final class TapHealthReconcilerTests: XCTestCase {
    func testReadyTapLostMarksNotReadyAndRequestsReinstall() {
        let decision = TapHealthReconciler.evaluate(
            isAccessibilityTrusted: true,
            isEventTapReady: false
        )

        XCTAssertTrue(decision.isAccessibilityTrusted)
        XCTAssertFalse(decision.isEventTapReady)
        XCTAssertFalse(decision.shouldStopTap)
        XCTAssertTrue(decision.shouldUpdateSlotSnapshot)
        XCTAssertTrue(decision.shouldInstallTap)
        XCTAssertTrue(decision.shouldRetryInstall)
    }

    func testPermissionRevokedStopsTapAndMarksNotReady() {
        let decision = TapHealthReconciler.evaluate(
            isAccessibilityTrusted: false,
            isEventTapReady: true
        )

        XCTAssertFalse(decision.isAccessibilityTrusted)
        XCTAssertFalse(decision.isEventTapReady)
        XCTAssertTrue(decision.shouldStopTap)
        XCTAssertFalse(decision.shouldUpdateSlotSnapshot)
        XCTAssertFalse(decision.shouldInstallTap)
        XCTAssertFalse(decision.shouldRetryInstall)
    }

    func testInstallFailureKeepsNotReadyAndRetryActive() {
        let decision = TapHealthReconciler.evaluate(
            isAccessibilityTrusted: true,
            isEventTapReady: false,
            installAttempt: .failed
        )

        XCTAssertTrue(decision.isAccessibilityTrusted)
        XCTAssertFalse(decision.isEventTapReady)
        XCTAssertFalse(decision.shouldStopTap)
        XCTAssertFalse(decision.shouldUpdateSlotSnapshot)
        XCTAssertFalse(decision.shouldInstallTap)
        XCTAssertTrue(decision.shouldRetryInstall)
    }
}
