import XCTest
@testable import DockTap

final class AppTextTests: XCTestCase {
    func testDockShortcutCountTitleUsesSingularAndPlural() {
        XCTAssertEqual(AppText.DockShortcuts.countTitle(1), "1 Dock shortcut")
        XCTAssertEqual(AppText.DockShortcuts.countTitle(0), "0 Dock shortcuts")
        XCTAssertEqual(AppText.DockShortcuts.countTitle(2), "2 Dock shortcuts")
    }

    func testMenuCommandNamesMatchM3Copy() {
        XCTAssertEqual(AppText.Menu.showDockMapping, "Show Dock Mapping")
        XCTAssertEqual(AppText.Menu.updateDockShortcuts, "Update Dock Shortcuts")
        XCTAssertEqual(AppText.Menu.triggerModifierTitle("Left Option"), "Trigger Modifier: Left Option")
    }

    func testAboutCombinesAppNameAndVersionWithSingleSpace() {
        XCTAssertEqual(AppText.Menu.about(appName: "Dock Tap", version: "0.1.0"), "Dock Tap 0.1.0")
    }
}
