import XCTest
@testable import DockTap

final class TriggerModifierPresetTests: XCTestCase {
    func testRawValuesAndOrderAreStable() {
        XCTAssertEqual(
            TriggerModifierPreset.allCases.map(\.rawValue),
            ["leftOption", "leftCommand", "leftControl", "rightOption", "rightCommand"]
        )
    }

    func testMenuTitlesAndShortcutLabelPrefixes() {
        XCTAssertEqual(TriggerModifierPreset.leftOption.menuTitle, "Left Option")
        XCTAssertEqual(TriggerModifierPreset.leftCommand.menuTitle, "Left Command")
        XCTAssertEqual(TriggerModifierPreset.leftControl.menuTitle, "Left Control")
        XCTAssertEqual(TriggerModifierPreset.rightOption.menuTitle, "Right Option")
        XCTAssertEqual(TriggerModifierPreset.rightCommand.menuTitle, "Right Command")

        XCTAssertEqual(TriggerModifierPreset.leftOption.shortcutLabel(forShortcutIndex: 0), "Left Option+1")
        XCTAssertEqual(TriggerModifierPreset.leftCommand.shortcutLabel(forShortcutIndex: 9), "Left Command+0")
        XCTAssertEqual(TriggerModifierPreset.rightCommand.shortcutLabel(forKeyLabel: "`"), "Right Command+`")
    }

    func testDefaultPresetIsLeftOption() {
        XCTAssertEqual(TriggerModifierPreset.defaultPreset, .leftOption)
    }

    func testSelectedPhysicalKeySemantics() {
        for preset in TriggerModifierPreset.allCases {
            var state = ModifierState()
            XCTAssertFalse(preset.selectedPhysicalKeyIsDown(in: state.snapshot))

            state.setPhysicalKey(preset.physicalKeyCode, isDown: true)
            XCTAssertTrue(preset.selectedPhysicalKeyIsDown(in: state.snapshot), preset.rawValue)

            state.setPhysicalKey(preset.physicalKeyCode, isDown: false)
            XCTAssertFalse(preset.selectedPhysicalKeyIsDown(in: state.snapshot), preset.rawValue)
        }
    }
}
