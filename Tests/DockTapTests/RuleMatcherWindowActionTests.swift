import XCTest
@testable import DockTap

final class RuleMatcherWindowActionTests: XCTestCase {
    private let decider = KeyEventDecider()

    func testWindowActionKeysMatchWhenEnabled() {
        let expectations: [(UInt16, WindowAction, String)] = [
            (KeyCodes.leftArrow, .leftHalf, "Left Option+←"),
            (KeyCodes.rightArrow, .rightHalf, "Left Option+→"),
            (KeyCodes.upArrow, .topHalf, "Left Option+↑"),
            (KeyCodes.downArrow, .bottomHalf, "Left Option+↓"),
            (KeyCodes.returnKey, .maximize, "Left Option+Return"),
            (KeyCodes.space, .center, "Left Option+Space")
        ]

        for (keyCode, action, shortcutLabel) in expectations {
            let decision = decide(keyCode: keyCode, windowActionsEnabled: true)

            XCTAssertTrue(decision.consumesEvent, "\(KeyCodes.label(for: keyCode)) should be consumed")
            XCTAssertEqual(decision.intent, .windowAction(action, shortcutLabel: shortcutLabel))
        }
    }

    func testWindowActionKeysPassThroughWhenDisabled() {
        for keyCode in [KeyCodes.leftArrow, KeyCodes.rightArrow, KeyCodes.upArrow, KeyCodes.downArrow, KeyCodes.returnKey, KeyCodes.space] {
            let decision = decide(keyCode: keyCode, windowActionsEnabled: false)

            XCTAssertFalse(decision.consumesEvent, "\(KeyCodes.label(for: keyCode)) should pass through")
            XCTAssertNil(decision.intent)
        }
    }

    func testWindowActionKeysRequireMatchingModifier() {
        let decision = decide(
            keyCode: KeyCodes.leftArrow,
            modifiers: modifiers(with: [KeyCodes.rightCommand]),
            windowActionsEnabled: true
        )

        XCTAssertFalse(decision.consumesEvent)
        XCTAssertNil(decision.intent)
    }

    func testShiftStillRejectsWindowActionKeys() {
        let decision = decide(
            keyCode: KeyCodes.leftArrow,
            modifiers: modifiers(with: [KeyCodes.leftOption, KeyCodes.leftShift]),
            windowActionsEnabled: true
        )

        XCTAssertFalse(decision.consumesEvent)
        XCTAssertNil(decision.intent)
    }

    func testDigitsAndBacktickStillMatchWhenWindowActionsAreEnabled() {
        let one = decide(keyCode: KeyCodes.one, slots: snapshot(appCount: 1), windowActionsEnabled: true)
        let backtick = decide(keyCode: KeyCodes.backtick, windowActionsEnabled: true)

        XCTAssertEqual(one.intent?.label, "Left Option+1")
        XCTAssertTrue(one.consumesEvent)
        XCTAssertEqual(backtick.intent, .finder(shortcutLabel: "Left Option+`"))
        XCTAssertTrue(backtick.consumesEvent)
    }

    private func decide(
        keyCode: UInt16,
        modifiers: ModifierSnapshot? = nil,
        slots: DockSlotSnapshot = .empty,
        windowActionsEnabled: Bool
    ) -> KeyEventDecision {
        decider.decide(
            kind: .keyDown,
            keyCode: keyCode,
            modifiers: modifiers ?? self.modifiers(with: [KeyCodes.leftOption]),
            triggerModifier: .leftOption,
            slots: slots,
            windowActionsEnabled: windowActionsEnabled
        )
    }

    private func modifiers(with keyCodes: [UInt16]) -> ModifierSnapshot {
        var state = ModifierState()
        for keyCode in keyCodes {
            state.setPhysicalKey(keyCode, isDown: true)
        }
        return state.snapshot
    }

    private func snapshot(appCount: Int) -> DockSlotSnapshot {
        let store = DockSlotStore()
        store.replace(entries: (1...appCount).map { index in
            DockAppEntry(
                dockOrdinal: index,
                appURL: URL(fileURLWithPath: "/Applications/App\(index).app"),
                displayName: "App\(index)",
                bundleIdentifier: nil,
                isMissing: false
            )
        })
        return store.snapshot()
    }
}
