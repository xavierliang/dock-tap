import XCTest
@testable import DockTap

final class AppTextTests: XCTestCase {
    func testDockShortcutCountTitleUsesSingularAndPlural() {
        XCTAssertEqual(AppText.DockShortcuts.countTitle(1), "1 Dock shortcut")
        XCTAssertEqual(AppText.DockShortcuts.countTitle(0), "0 Dock shortcuts")
        XCTAssertEqual(AppText.DockShortcuts.countTitle(2), "2 Dock shortcuts")
    }

    func testMenuCommandNamesMatchM3Copy() {
        XCTAssertEqual(AppText.Menu.dockShortcuts, "Dock Shortcuts")
        XCTAssertEqual(AppText.Menu.updateDockShortcuts, "Update Dock Shortcuts")
        XCTAssertEqual(AppText.Menu.triggerModifierTitle("Left Option"), "Trigger Modifier: Left Option")
    }

    func testVersionTitleUsesCompactCopy() {
        XCTAssertEqual(AppText.Menu.versionTitle(version: "0.1.0"), "Version 0.1.0")
    }

    func testClosedLidCommandAndWarningCopy() {
        XCTAssertEqual(AppText.ClosedLid.submenuTitle, "Closed-Lid Keep Awake")
        XCTAssertEqual(AppText.ClosedLid.enableOneHour, "Enable for 1 Hour")
        XCTAssertEqual(AppText.ClosedLid.enableIndefinitely, "Enable Indefinitely")
        XCTAssertEqual(AppText.ClosedLid.stopNow, "Stop Now")
        XCTAssertEqual(AppText.ClosedLid.warningTitle, "Enable Closed-Lid Keep Awake?")
        XCTAssertTrue(AppText.ClosedLid.warningBody.contains("pmset disablesleep"))
        XCTAssertTrue(AppText.ClosedLid.warningBody.contains("battery drain and heat"))
        XCTAssertEqual(AppText.ClosedLid.warningContinue, "Continue")
        XCTAssertEqual(AppText.ClosedLid.warningCancel, "Cancel")
    }

    func testClosedLidHelperApprovalAndRecoveryCopy() {
        XCTAssertEqual(AppText.ClosedLid.helperApprovalRequired, "Helper approval required")
        XCTAssertTrue(AppText.ClosedLid.helperApprovalBody.contains("Login Items & Extensions"))
        XCTAssertEqual(AppText.ClosedLid.openLoginItemsSettings, "Open Login Items Settings...")
        XCTAssertEqual(AppText.ClosedLid.stopFailureTitle, "Closed-Lid Keep Awake Could Not Stop")
        XCTAssertEqual(
            AppText.ClosedLid.manualRecovery,
            "Run sudo pmset -a disablesleep 0 to restore normal lid sleep."
        )
        XCTAssertEqual(AppText.ClosedLid.updateBlockedTitle, "Update Blocked")
    }

    func testClosedLidStatusCopy() {
        XCTAssertEqual(AppText.ClosedLid.statusTitle(for: .off), "Off")
        XCTAssertEqual(AppText.ClosedLid.statusTitle(for: .starting), "Starting…")
        XCTAssertEqual(AppText.ClosedLid.statusTitle(for: .stopping), "Stopping…")
        XCTAssertEqual(AppText.ClosedLid.statusTitle(for: .activeIndefinite), "On indefinitely")
        XCTAssertEqual(AppText.ClosedLid.statusTitle(for: .requiresApproval), "Helper approval required")
        XCTAssertEqual(AppText.ClosedLid.statusTitle(for: .error("helper failed")), "Error: helper failed")
        XCTAssertTrue(
            AppText.ClosedLid.statusTitle(for: .errorWithActiveSession("restore failed"))
                .contains("sudo pmset -a disablesleep 0")
        )
        XCTAssertTrue(
            AppText.ClosedLid.statusTitle(for: .stopFailed("restore failed"))
                .contains("sudo pmset -a disablesleep 0")
        )
    }
}
