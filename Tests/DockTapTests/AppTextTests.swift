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
}
