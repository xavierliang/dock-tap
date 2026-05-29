import CoreGraphics
import XCTest
@testable import DockTap

final class KeyCodesDeviceFlagTests: XCTestCase {
    // Mirrors EventTapController.isModifierDown: rebuild a snapshot purely from an
    // event's CGEventFlags, the same way the live tap now reads modifier state.
    private func snapshot(from flags: CGEventFlags) -> ModifierSnapshot {
        var state = ModifierState()
        state.resync { keyCode in
            guard let mask = KeyCodes.deviceFlag(for: keyCode) else { return false }
            return flags.contains(mask)
        }
        return state.snapshot
    }

    func testLeftAndRightModifiersUseDistinctBits() {
        let pairs: [(UInt16, UInt16)] = [
            (KeyCodes.leftOption, KeyCodes.rightOption),
            (KeyCodes.leftCommand, KeyCodes.rightCommand),
            (KeyCodes.leftControl, KeyCodes.rightControl),
            (KeyCodes.leftShift, KeyCodes.rightShift)
        ]
        for (left, right) in pairs {
            let leftMask = KeyCodes.deviceFlag(for: left)
            let rightMask = KeyCodes.deviceFlag(for: right)
            XCTAssertNotNil(leftMask, KeyCodes.label(for: left))
            XCTAssertNotNil(rightMask, KeyCodes.label(for: right))
            XCTAssertNotEqual(leftMask, rightMask, KeyCodes.label(for: left))
        }
    }

    func testRawDeviceFlagValues() {
        XCTAssertEqual(KeyCodes.deviceFlag(for: KeyCodes.leftControl), CGEventFlags(rawValue: 0x0000_0001))
        XCTAssertEqual(KeyCodes.deviceFlag(for: KeyCodes.leftShift), CGEventFlags(rawValue: 0x0000_0002))
        XCTAssertEqual(KeyCodes.deviceFlag(for: KeyCodes.rightShift), CGEventFlags(rawValue: 0x0000_0004))
        XCTAssertEqual(KeyCodes.deviceFlag(for: KeyCodes.leftCommand), CGEventFlags(rawValue: 0x0000_0008))
        XCTAssertEqual(KeyCodes.deviceFlag(for: KeyCodes.rightCommand), CGEventFlags(rawValue: 0x0000_0010))
        XCTAssertEqual(KeyCodes.deviceFlag(for: KeyCodes.leftOption), CGEventFlags(rawValue: 0x0000_0020))
        XCTAssertEqual(KeyCodes.deviceFlag(for: KeyCodes.rightOption), CGEventFlags(rawValue: 0x0000_0040))
        XCTAssertEqual(KeyCodes.deviceFlag(for: KeyCodes.rightControl), CGEventFlags(rawValue: 0x0000_2000))
    }

    func testNonModifierKeysHaveNoDeviceFlag() {
        XCTAssertNil(KeyCodes.deviceFlag(for: KeyCodes.one))
        XCTAssertNil(KeyCodes.deviceFlag(for: KeyCodes.backtick))
        XCTAssertNil(KeyCodes.deviceFlag(for: KeyCodes.leftArrow))
    }

    // The bug: choosing Left Option also fired on Right Option. With device-dependent
    // flags, a right-only event must not satisfy the Left Option preset (and vice versa).
    func testRightOptionDoesNotTriggerLeftOptionPreset() {
        let snap = snapshot(from: KeyCodes.deviceFlag(for: KeyCodes.rightOption)!)

        XCTAssertFalse(snap.leftOption)
        XCTAssertTrue(snap.rightOption)
        XCTAssertFalse(TriggerModifierPreset.leftOption.matches(snap))
        XCTAssertTrue(TriggerModifierPreset.rightOption.matches(snap))
    }

    func testLeftOptionTriggersOnlyLeftOptionPreset() {
        let snap = snapshot(from: KeyCodes.deviceFlag(for: KeyCodes.leftOption)!)

        XCTAssertTrue(snap.leftOption)
        XCTAssertFalse(snap.rightOption)
        XCTAssertTrue(TriggerModifierPreset.leftOption.matches(snap))
        XCTAssertFalse(TriggerModifierPreset.rightOption.matches(snap))
    }
}
