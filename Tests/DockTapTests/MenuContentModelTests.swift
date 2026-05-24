import XCTest
@testable import DockTap

final class MenuContentModelTests: XCTestCase {
    func testExamplesAreGenericAndDoNotListDockApps() {
        let model = MenuContentModel(
            dockRows: (0..<10).map { row(index: $0, name: "Dock App \($0 + 1)") },
            selectedPreset: .leftOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true
        )

        XCTAssertEqual(
            model.exampleRows.map(\.title),
            [
                "Left Option+1  First Dock app",
                "Left Option+2  Second Dock app",
                "Left Option+0  Tenth Dock app",
                "Left Option+`  Finder"
            ]
        )
        XCTAssertFalse(model.exampleRows.contains { $0.title.contains("Dock App") })
    }

    func testMappingAlwaysContainsExactlyTenDockShortcutRowsWithoutFinder() {
        let model = MenuContentModel(
            dockRows: [
                row(index: 0, name: "Safari", status: .active),
                row(index: 3, name: "Mail", status: .notRunning)
            ],
            selectedPreset: .rightCommand,
            isAccessibilityTrusted: true,
            isEventTapReady: true
        )

        XCTAssertEqual(model.mappingRows.count, 10)
        XCTAssertEqual(model.mappingRows.filter(\.isAssigned).count, 2)
        XCTAssertEqual(model.mappingRows[0].title, "Right Command+1  Safari [active]")
        XCTAssertEqual(model.mappingRows[1].title, "Right Command+2  Unassigned")
        XCTAssertEqual(model.mappingRows[3].title, "Right Command+4  Mail [not running]")
        XCTAssertFalse(model.mappingRows.contains { $0.title.contains("Finder") })
    }

    func testTriggerRowsMarkExactlyTheSelectedPreset() {
        let model = MenuContentModel(
            dockRows: [],
            selectedPreset: .rightOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true
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
            isEventTapReady: true
        )

        XCTAssertEqual(model.updateDockShortcutsTitle, "Update Dock Shortcuts")
    }

    func testSummaryUsesAssignedShortcutCountCappedAtTenWithoutDiagnosticDetail() {
        let model = MenuContentModel(
            dockRows: (0..<12).map { row(index: $0, name: "Dock App \($0 + 1)") },
            selectedPreset: .leftControl,
            isAccessibilityTrusted: true,
            isEventTapReady: true
        )

        XCTAssertEqual(model.assignedShortcutCount, 10)
        XCTAssertEqual(model.summaryTitle, "Ready | Left Control | 10 Dock shortcuts")
        XCTAssertFalse(model.summaryTitle.contains("skipped"))
        XCTAssertFalse(model.summaryTitle.contains("more"))
    }

    func testSummaryShowsMissingAccessibilityPermissionAndActionsOnlyWhenNeeded() {
        let missing = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftOption,
            isAccessibilityTrusted: false,
            isEventTapReady: false
        )
        let trusted = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftOption,
            isAccessibilityTrusted: true,
            isEventTapReady: true
        )

        XCTAssertEqual(missing.summaryTitle, "Missing Accessibility Permission | Left Option | 0 Dock shortcuts")
        XCTAssertEqual(missing.checkAccessibilityTitle, "Check Accessibility")
        XCTAssertEqual(missing.openAccessibilitySettingsTitle, "Open Accessibility Settings")
        XCTAssertNil(trusted.checkAccessibilityTitle)
        XCTAssertNil(trusted.openAccessibilitySettingsTitle)
    }

    func testSummaryDoesNotShowStartingWhenAccessibilityIsTrustedButTapIsNotReady() {
        let model = MenuContentModel(
            dockRows: [],
            selectedPreset: .leftCommand,
            isAccessibilityTrusted: true,
            isEventTapReady: false
        )

        XCTAssertEqual(model.summaryTitle, "Ready | Left Command | 0 Dock shortcuts")
        XCTAssertFalse(model.summaryTitle.contains("Starting"))
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
