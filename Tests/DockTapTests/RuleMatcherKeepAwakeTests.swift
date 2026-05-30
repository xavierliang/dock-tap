import XCTest
@testable import DockTap

final class RuleMatcherKeepAwakeTests: XCTestCase {
    private let decider = KeyEventDecider()

    func testKeepAwakeKeysMatchForAllTriggerPresets() {
        for preset in TriggerModifierPreset.allCases {
            for (keyCode, action) in keepAwakeExpectations {
                let decision = decide(keyCode: keyCode, triggerModifier: preset)

                XCTAssertTrue(
                    decision.consumesEvent,
                    "\(preset.rawValue) \(KeyCodes.label(for: keyCode)) should be consumed"
                )
                XCTAssertEqual(
                    decision.intent,
                    .keepAwake(action, shortcutLabel: preset.shortcutLabel(forKeyLabel: action.shortcutKeyLabel))
                )
            }
        }
    }

    func testKeepAwakeKeysAreIndependentOfWindowActionsToggle() {
        let disabled = decide(keyCode: KeyCodes.a, windowActionsEnabled: false)
        let enabled = decide(keyCode: KeyCodes.a, windowActionsEnabled: true)

        XCTAssertEqual(disabled.intent, .keepAwake(.oneHour, shortcutLabel: "Left Option+A"))
        XCTAssertTrue(disabled.consumesEvent)
        XCTAssertEqual(enabled.intent, .keepAwake(.oneHour, shortcutLabel: "Left Option+A"))
        XCTAssertTrue(enabled.consumesEvent)
    }

    func testKeepAwakeKeysRequireMatchingModifier() {
        let decision = decide(
            keyCode: KeyCodes.a,
            modifiers: modifiers(with: [KeyCodes.rightCommand])
        )

        XCTAssertFalse(decision.consumesEvent)
        XCTAssertNil(decision.intent)
    }

    func testShiftRejectsKeepAwakeKeys() {
        for (keyCode, _) in keepAwakeExpectations {
            let decision = decide(
                keyCode: keyCode,
                modifiers: modifiers(with: [KeyCodes.leftOption, KeyCodes.leftShift])
            )

            XCTAssertFalse(decision.consumesEvent)
            XCTAssertNil(decision.intent)
        }
    }

    func testKeepAwakeKeysPassThroughOnKeyUp() {
        let decision = decider.decide(
            kind: .keyUp,
            keyCode: KeyCodes.a,
            modifiers: modifiers(with: [KeyCodes.leftOption]),
            triggerModifier: .leftOption,
            slots: .empty,
            windowActionsEnabled: false
        )

        XCTAssertFalse(decision.consumesEvent)
        XCTAssertNil(decision.intent)
    }

    private func decide(
        keyCode: UInt16,
        triggerModifier: TriggerModifierPreset = .leftOption,
        modifiers: ModifierSnapshot? = nil,
        windowActionsEnabled: Bool = false
    ) -> KeyEventDecision {
        decider.decide(
            kind: .keyDown,
            keyCode: keyCode,
            modifiers: modifiers ?? self.modifiers(with: [triggerModifier.physicalKeyCode]),
            triggerModifier: triggerModifier,
            slots: .empty,
            windowActionsEnabled: windowActionsEnabled
        )
    }

    private var keepAwakeExpectations: [(UInt16, KeepAwakeShortcut)] {
        [
            (KeyCodes.a, .oneHour),
            (KeyCodes.s, .indefinite),
            (KeyCodes.d, .stop)
        ]
    }

    private func modifiers(with keyCodes: [UInt16]) -> ModifierSnapshot {
        var state = ModifierState()
        for keyCode in keyCodes {
            state.setPhysicalKey(keyCode, isDown: true)
        }
        return state.snapshot
    }
}
