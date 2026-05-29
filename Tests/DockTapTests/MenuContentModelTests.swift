import XCTest
@testable import DockTap

final class MenuContentModelTests: XCTestCase {
    func testDockShortcutsSubmenuIncludesFinderShortcutTitle() {
        let model = MenuContentModel(
            dockRows: (0..<10).map { row(index: $0, name: "Dock App \($0 + 1)") },
            selectedPreset: .leftOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )

        XCTAssertEqual(model.dockShortcutsTitle, "Dock Shortcuts")
        XCTAssertEqual(model.finderShortcutTitle, "Left Option+`  Finder")
    }

    func testMappingAlwaysContainsExactlyTenDockShortcutRows() {
        let model = MenuContentModel(
            dockRows: [
                row(index: 0, name: "Safari", status: .active),
                row(index: 3, name: "Mail", status: .notRunning)
            ],
            selectedPreset: .rightCommand,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )

        XCTAssertEqual(model.mappingRows.count, 10)
        XCTAssertEqual(model.mappingRows.filter(\.isAssigned).count, 2)
        XCTAssertEqual(model.mappingRows[0].title, "Right Command+1  Safari [active]")
        XCTAssertEqual(model.mappingRows[1].title, "Right Command+2  Unassigned")
        XCTAssertEqual(model.mappingRows[3].title, "Right Command+4  Mail [not running]")
    }

    func testTriggerRowsMarkExactlyTheSelectedPreset() {
        let model = MenuContentModel(
            dockRows: [],
            selectedPreset: .rightOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )

        XCTAssertEqual(model.triggerModifierTitle, "Trigger Modifier: Right Option")
        XCTAssertEqual(model.triggerRows.map(\.title), TriggerModifierPreset.allCases.map(\.menuTitle))
        XCTAssertEqual(model.triggerRows.filter(\.isSelected).map(\.preset), [.rightOption])
    }

    func testManualUpdateLabelUsesProductCopy() {
        let model = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )

        XCTAssertEqual(model.updateDockShortcutsTitle, "Update Dock Shortcuts")
    }

    func testSummaryUsesAssignedShortcutCountCappedAtTenWithoutDiagnosticDetail() {
        let model = MenuContentModel(
            dockRows: (0..<12).map { row(index: $0, name: "Dock App \($0 + 1)") },
            selectedPreset: .leftControl,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )

        XCTAssertEqual(model.assignedShortcutCount, 10)
        XCTAssertEqual(model.summaryTitle, "Ready · Left Control · 10 Dock shortcuts")
        XCTAssertFalse(model.summaryTitle.contains("skipped"))
        XCTAssertFalse(model.summaryTitle.contains("more"))
    }

    func testSummaryShowsMissingAccessibilityPermissionAndActionsOnlyWhenNeeded() {
        let missing = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftOption,
            isAccessibilityTrusted: false,
            isEventTapReady: false,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )
        let trusted = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )

        XCTAssertEqual(missing.summaryTitle, "Missing Accessibility Permission · Left Option · 0 Dock shortcuts")
        XCTAssertEqual(missing.checkAccessibilityTitle, "Check Accessibility")
        XCTAssertEqual(missing.openAccessibilitySettingsTitle, "Open Accessibility Settings")
        XCTAssertNil(trusted.checkAccessibilityTitle)
        XCTAssertNil(trusted.openAccessibilitySettingsTitle)
    }

    func testSummaryStatusPrioritizesAccessibilityThenTapReadiness() {
        let missing = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftOption,
            isAccessibilityTrusted: false,
            isEventTapReady: false,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )
        let starting = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftCommand,
            isAccessibilityTrusted: true,
            isEventTapReady: false,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )
        let ready = MenuContentModel(
            dockRows: [],
            selectedPreset: .rightOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )

        XCTAssertEqual(missing.summaryTitle, "Missing Accessibility Permission · Left Option · 0 Dock shortcuts")
        XCTAssertEqual(starting.summaryTitle, "Starting · Left Command · 0 Dock shortcuts")
        XCTAssertEqual(ready.summaryTitle, "Ready · Right Option · 0 Dock shortcuts")
    }

    func testSummaryShowsStartingWhenAccessibilityIsTrustedButTapIsNotReady() {
        let model = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftCommand,
            isAccessibilityTrusted: true,
            isEventTapReady: false,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )

        XCTAssertEqual(model.summaryTitle, "Starting · Left Command · 0 Dock shortcuts")
    }

    func testWindowSnapToggleAndRowsUseSelectedPreset() {
        let model = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: true,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )

        XCTAssertEqual(model.windowSnapToggleTitle, "Enable Window Snap")
        XCTAssertTrue(model.windowSnapToggleIsOn)
        XCTAssertEqual(model.windowSnapSubmenuTitle, "Window Snap Bindings")
        XCTAssertEqual(model.windowSnapRows.map(\.action), WindowAction.allCases)
        XCTAssertEqual(
            model.windowSnapRows.map(\.title),
            [
                "Left Option+←  Left Half",
                "Left Option+→  Right Half",
                "Left Option+↑  Top Half",
                "Left Option+↓  Bottom Half",
                "Left Option+Return  Maximize",
                "Left Option+Space  Center"
            ]
        )
    }

    func testClosedLidMenuOffStateEnablesStartCommandsOnly() {
        let model = model(closedLidState: .off)

        XCTAssertEqual(model.closedLidMenu.title, "Closed-Lid Keep Awake")
        XCTAssertEqual(model.closedLidMenu.statusTitle, "Off")
        XCTAssertEqual(model.closedLidMenu.enableOneHourTitle, "Enable for 1 Hour")
        XCTAssertTrue(model.closedLidMenu.enableOneHourIsEnabled)
        XCTAssertFalse(model.closedLidMenu.enableOneHourIsChecked)
        XCTAssertEqual(model.closedLidMenu.enableIndefinitelyTitle, "Enable Indefinitely")
        XCTAssertTrue(model.closedLidMenu.enableIndefinitelyIsEnabled)
        XCTAssertFalse(model.closedLidMenu.enableIndefinitelyIsChecked)
        XCTAssertEqual(model.closedLidMenu.stopNowTitle, "Stop Now")
        XCTAssertFalse(model.closedLidMenu.stopNowIsEnabled)
        XCTAssertNil(model.closedLidMenu.openApprovalSettingsTitle)
    }

    func testClosedLidMenuActiveTimedDisablesModeSwitchingAndChecksTimedCommand() {
        let endDate = Date(timeIntervalSinceReferenceDate: 8_000)
        let model = model(closedLidState: .activeTimed(endDate: endDate))
        let expectedStatus = AppText.ClosedLid.onUntil(
            time: DateFormatter.localizedString(from: endDate, dateStyle: .none, timeStyle: .short)
        )

        XCTAssertEqual(model.closedLidMenu.statusTitle, expectedStatus)
        XCTAssertFalse(model.closedLidMenu.enableOneHourIsEnabled)
        XCTAssertTrue(model.closedLidMenu.enableOneHourIsChecked)
        XCTAssertFalse(model.closedLidMenu.enableIndefinitelyIsEnabled)
        XCTAssertFalse(model.closedLidMenu.enableIndefinitelyIsChecked)
        XCTAssertTrue(model.closedLidMenu.stopNowIsEnabled)
    }

    func testClosedLidMenuActiveIndefiniteDisablesModeSwitchingAndChecksIndefiniteCommand() {
        let model = model(closedLidState: .activeIndefinite)

        XCTAssertEqual(model.closedLidMenu.statusTitle, "On indefinitely")
        XCTAssertFalse(model.closedLidMenu.enableOneHourIsEnabled)
        XCTAssertFalse(model.closedLidMenu.enableOneHourIsChecked)
        XCTAssertFalse(model.closedLidMenu.enableIndefinitelyIsEnabled)
        XCTAssertTrue(model.closedLidMenu.enableIndefinitelyIsChecked)
        XCTAssertTrue(model.closedLidMenu.stopNowIsEnabled)
    }

    func testClosedLidMenuBusyAndApprovalStatesDisableStartCommands() {
        let starting = model(closedLidState: .starting).closedLidMenu
        let stopping = model(closedLidState: .stopping).closedLidMenu
        let approval = model(closedLidState: .requiresApproval).closedLidMenu

        XCTAssertEqual(starting.statusTitle, "Starting…")
        XCTAssertFalse(starting.enableOneHourIsEnabled)
        XCTAssertTrue(starting.stopNowIsEnabled)

        XCTAssertEqual(stopping.statusTitle, "Stopping…")
        XCTAssertFalse(stopping.enableIndefinitelyIsEnabled)
        XCTAssertFalse(stopping.stopNowIsEnabled)

        XCTAssertEqual(approval.statusTitle, "Helper approval required")
        XCTAssertFalse(approval.enableOneHourIsEnabled)
        XCTAssertFalse(approval.stopNowIsEnabled)
        XCTAssertEqual(approval.openApprovalSettingsTitle, "Open Login Items Settings...")
    }

    func testClosedLidMenuErrorAllowsRetryButStopFailureKeepsRecoveryAvailable() {
        let error = model(closedLidState: .error("helper unavailable")).closedLidMenu
        let stopFailed = model(closedLidState: .stopFailed("restore failed")).closedLidMenu

        XCTAssertEqual(error.statusTitle, "Error: helper unavailable")
        XCTAssertTrue(error.enableOneHourIsEnabled)
        XCTAssertFalse(error.stopNowIsEnabled)

        XCTAssertTrue(stopFailed.statusTitle.contains("Error: restore failed."))
        XCTAssertTrue(stopFailed.statusTitle.contains("sudo pmset -a disablesleep 0"))
        XCTAssertFalse(stopFailed.enableOneHourIsEnabled)
        XCTAssertTrue(stopFailed.stopNowIsEnabled)
    }

    func testVersionTitleShowsVersion() {
        let model = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "1.2.3"
        )

        XCTAssertEqual(model.versionTitle, "Version 1.2.3")
    }

    func testCheckForUpdatesTitleAlwaysAvailableAndUpdateAvailableTitleReflectsVersion() {
        let withoutUpdate = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.1.0"
        )
        let withUpdate = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            appName: "Dock Tap",
            appVersion: "0.1.0",
            availableUpdateVersion: "0.2.0"
        )

        XCTAssertEqual(withoutUpdate.checkForUpdatesTitle, "Check for Updates…")
        XCTAssertNil(withoutUpdate.updateAvailableTitle)
        XCTAssertEqual(withUpdate.checkForUpdatesTitle, "Check for Updates…")
        XCTAssertEqual(withUpdate.updateAvailableTitle, "Update Available: v0.2.0")
    }

    private func model(closedLidState: ClosedLidKeepAwakeState) -> MenuContentModel {
        MenuContentModel(
            dockRows: [],
            selectedPreset: .leftOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            closedLidState: closedLidState,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        )
    }

    private func row(
        index: Int,
        name: String,
        status: DockSlotStatus = .running
    ) -> DockSlotMenuRow {
        DockSlotMenuRow(
            target: DockSlotTarget(
                id: "slot-\(index)",
                shortcutIndex: index,
                dockOrdinal: index + 1,
                appURL: URL(fileURLWithPath: "/Applications/\(name).app"),
                displayName: name,
                bundleIdentifier: "test.\(index)",
                isMissing: false
            ),
            status: status
        )
    }
}
