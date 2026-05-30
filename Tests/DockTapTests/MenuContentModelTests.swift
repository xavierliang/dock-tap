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

    private typealias ClosedLidAction = MenuContentModel.ClosedLidMenu.Action

    func testClosedLidMenuOffStateShowsEnableCommandsWithShortcutHints() {
        let items = model(closedLidState: .off).closedLidMenu.items
        let expectedActions: [ClosedLidAction?] = [nil, .enableOneHour, .enableIndefinitely]

        XCTAssertEqual(items.map(\.title), [
            "Closed-Lid Keep Awake",
            "Left Option+A  Enable for 1 Hour",
            "Left Option+S  Enable Indefinitely"
        ])
        XCTAssertEqual(items.map(\.action), expectedActions)
    }

    func testClosedLidMenuActiveTimedShowsStatusAndStopOnly() {
        let endDate = Date(timeIntervalSinceReferenceDate: 8_000)
        let items = model(closedLidState: .activeTimed(endDate: endDate)).closedLidMenu.items
        let expectedStatus = AppText.ClosedLid.onUntil(
            time: DateFormatter.localizedString(from: endDate, dateStyle: .none, timeStyle: .short)
        )
        let expectedActions: [ClosedLidAction?] = [nil, nil, .stop]

        XCTAssertEqual(items.map(\.title), [
            "Closed-Lid Keep Awake",
            expectedStatus,
            "Left Option+D  Stop Now"
        ])
        XCTAssertEqual(items.map(\.action), expectedActions)
    }

    func testClosedLidMenuActiveIndefiniteShowsStatusAndStopOnly() {
        let items = model(closedLidState: .activeIndefinite).closedLidMenu.items
        let expectedActions: [ClosedLidAction?] = [nil, nil, .stop]

        XCTAssertEqual(items.map(\.title), [
            "Closed-Lid Keep Awake",
            "On indefinitely",
            "Left Option+D  Stop Now"
        ])
        XCTAssertEqual(items.map(\.action), expectedActions)
    }

    func testClosedLidMenuShortcutHintsFollowSelectedPreset() {
        let items = MenuContentModel(
            dockRows: [],
            selectedPreset: .rightCommand,
            isAccessibilityTrusted: true,
            isEventTapReady: true,
            windowActionsEnabled: false,
            closedLidState: .off,
            appName: "Dock Tap",
            appVersion: "0.0.0"
        ).closedLidMenu.items

        XCTAssertEqual(items.map(\.title), [
            "Closed-Lid Keep Awake",
            "Right Command+A  Enable for 1 Hour",
            "Right Command+S  Enable Indefinitely"
        ])
    }

    func testClosedLidMenuBusyStatesShowStatusLineOnly() {
        let starting = model(closedLidState: .starting).closedLidMenu.items
        let stopping = model(closedLidState: .stopping).closedLidMenu.items
        let expectedActions: [ClosedLidAction?] = [nil, nil]

        XCTAssertEqual(starting.map(\.title), ["Closed-Lid Keep Awake", "Starting…"])
        XCTAssertEqual(starting.map(\.action), expectedActions)
        XCTAssertEqual(stopping.map(\.title), ["Closed-Lid Keep Awake", "Stopping…"])
        XCTAssertEqual(stopping.map(\.action), expectedActions)
        XCTAssertTrue(ClosedLidKeepAwakeState.starting.canStopSession)
    }

    func testClosedLidMenuRequiresApprovalShowsApprovalLink() {
        let items = model(closedLidState: .requiresApproval).closedLidMenu.items
        let expectedActions: [ClosedLidAction?] = [nil, nil, .openApprovalSettings]

        XCTAssertEqual(items.map(\.title), [
            "Closed-Lid Keep Awake",
            "Helper approval required",
            "Open Login Items Settings..."
        ])
        XCTAssertEqual(items.map(\.action), expectedActions)
    }

    func testClosedLidMenuErrorAllowsRetryWhileStopFailureKeepsStop() {
        let error = model(closedLidState: .error("helper unavailable")).closedLidMenu.items
        let activeError = model(closedLidState: .errorWithActiveSession("restore failed")).closedLidMenu.items
        let stopFailed = model(closedLidState: .stopFailed("restore failed")).closedLidMenu.items
        let errorActions: [ClosedLidAction?] = [nil, nil, .enableOneHour, .enableIndefinitely]
        let stopActions: [ClosedLidAction?] = [nil, nil, .stop]

        XCTAssertEqual(error.map(\.action), errorActions)
        XCTAssertEqual(error[1].title, "Error: helper unavailable")

        XCTAssertEqual(activeError.map(\.action), stopActions)
        XCTAssertTrue(activeError[1].title.contains("Error: restore failed."))
        XCTAssertTrue(activeError[1].title.contains("sudo pmset -a disablesleep 0"))

        XCTAssertEqual(stopFailed.map(\.action), stopActions)
        XCTAssertTrue(stopFailed[1].title.contains("Error: restore failed."))
        XCTAssertTrue(stopFailed[1].title.contains("sudo pmset -a disablesleep 0"))
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
