import XCTest
@testable import DockTap

final class ModifierStateTests: XCTestCase {
    func testTracksLeftAndRightOptionIndependently() {
        var state = ModifierState()

        state.setPhysicalKey(KeyCodes.leftOption, isDown: true)
        XCTAssertTrue(state.snapshot.leftOption)
        XCTAssertFalse(state.snapshot.rightOption)

        state.setPhysicalKey(KeyCodes.rightOption, isDown: true)
        XCTAssertTrue(state.snapshot.leftOption)
        XCTAssertTrue(state.snapshot.rightOption)

        state.setPhysicalKey(KeyCodes.leftOption, isDown: false)
        XCTAssertFalse(state.snapshot.leftOption)
        XCTAssertTrue(state.snapshot.rightOption)
    }

    func testResyncUpdatesTrackedModifierKeys() {
        var state = ModifierState()
        state.setPhysicalKey(KeyCodes.leftOption, isDown: true)
        state.setPhysicalKey(KeyCodes.leftShift, isDown: true)

        let changes = state.resync { keyCode in
            keyCode == KeyCodes.rightOption || keyCode == KeyCodes.capsLock
        }

        XCTAssertFalse(state.snapshot.leftOption)
        XCTAssertFalse(state.snapshot.leftShift)
        XCTAssertTrue(state.snapshot.rightOption)
        XCTAssertTrue(state.snapshot.capsLock)
        XCTAssertTrue(changes.contains(ModifierChange(keyCode: KeyCodes.leftOption, isDown: false)))
        XCTAssertTrue(changes.contains(ModifierChange(keyCode: KeyCodes.rightOption, isDown: true)))
    }

    func testCapsLockAndFunctionAreRecordOnlyModifiers() {
        var state = ModifierState()
        state.setPhysicalKey(KeyCodes.leftOption, isDown: true)
        state.setPhysicalKey(KeyCodes.capsLock, isDown: true)
        state.setPhysicalKey(KeyCodes.function, isDown: true)

        XCTAssertTrue(state.snapshot.leftOption)
        XCTAssertTrue(state.snapshot.capsLock)
        XCTAssertTrue(state.snapshot.function)
        XCTAssertTrue(TriggerModifierPreset.leftOption.matches(state.snapshot))
    }

    func testPhysicalModifierLookupReadsTrackedSideKeys() {
        var state = ModifierState()
        let trackedKeys = [
            KeyCodes.leftOption,
            KeyCodes.rightOption,
            KeyCodes.leftShift,
            KeyCodes.rightShift,
            KeyCodes.leftCommand,
            KeyCodes.rightCommand,
            KeyCodes.leftControl,
            KeyCodes.rightControl,
            KeyCodes.capsLock,
            KeyCodes.function
        ]

        for keyCode in trackedKeys {
            state.setPhysicalKey(keyCode, isDown: true)
            XCTAssertTrue(state.snapshot.isPhysicalModifierDown(keyCode), KeyCodes.label(for: keyCode))
            state.setPhysicalKey(keyCode, isDown: false)
            XCTAssertFalse(state.snapshot.isPhysicalModifierDown(keyCode), KeyCodes.label(for: keyCode))
        }

        XCTAssertFalse(state.snapshot.isPhysicalModifierDown(KeyCodes.one))
    }
}
