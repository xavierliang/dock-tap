import XCTest
@testable import DockTap

final class RuleMatcherWindowActionTests: XCTestCase {
    private let decider = KeyEventDecider()

    func testWindowActionKeysMatchWhenEnabledForAllTriggerPresets() {
        for preset in TriggerModifierPreset.allCases {
            for (keyCode, action) in windowActionExpectations {
                let decision = decide(
                    keyCode: keyCode,
                    triggerModifier: preset,
                    windowActionsEnabled: true
                )

                XCTAssertTrue(
                    decision.consumesEvent,
                    "\(preset.rawValue) \(KeyCodes.label(for: keyCode)) should be consumed"
                )
                XCTAssertEqual(
                    decision.intent,
                    .windowAction(action, shortcutLabel: preset.shortcutLabel(forKeyLabel: action.shortcutKeyLabel))
                )
            }
        }
    }

    func testWindowActionKeysPassThroughWhenDisabledForAllTriggerPresets() {
        for preset in TriggerModifierPreset.allCases {
            for (keyCode, _) in windowActionExpectations {
                let decision = decide(
                    keyCode: keyCode,
                    triggerModifier: preset,
                    windowActionsEnabled: false
                )

                XCTAssertFalse(
                    decision.consumesEvent,
                    "\(preset.rawValue) \(KeyCodes.label(for: keyCode)) should pass through"
                )
                XCTAssertNil(decision.intent)
            }
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

    func testWindowActionsStillMatchWhenDockShortcutsAreDisabled() {
        let decision = decide(
            keyCode: KeyCodes.leftArrow,
            dockShortcutsEnabled: false,
            windowActionsEnabled: true
        )

        XCTAssertEqual(decision.intent, .windowAction(.leftHalf, shortcutLabel: "Left Option+←"))
        XCTAssertTrue(decision.consumesEvent)
    }

    private func decide(
        keyCode: UInt16,
        triggerModifier: TriggerModifierPreset = .leftOption,
        modifiers: ModifierSnapshot? = nil,
        slots: DockSlotSnapshot = .empty,
        dockShortcutsEnabled: Bool = true,
        windowActionsEnabled: Bool
    ) -> KeyEventDecision {
        decider.decide(
            kind: .keyDown,
            keyCode: keyCode,
            modifiers: modifiers ?? self.modifiers(with: [triggerModifier.physicalKeyCode]),
            triggerModifier: triggerModifier,
            slots: slots,
            dockShortcutsEnabled: dockShortcutsEnabled,
            windowActionsEnabled: windowActionsEnabled
        )
    }

    private var windowActionExpectations: [(UInt16, WindowAction)] {
        [
            (KeyCodes.leftArrow, .leftHalf),
            (KeyCodes.rightArrow, .rightHalf),
            (KeyCodes.upArrow, .topHalf),
            (KeyCodes.downArrow, .bottomHalf),
            (KeyCodes.returnKey, .maximize),
            (KeyCodes.space, .center)
        ]
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
