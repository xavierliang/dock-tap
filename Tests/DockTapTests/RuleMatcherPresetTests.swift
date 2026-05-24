import XCTest
@testable import DockTap

final class RuleMatcherPresetTests: XCTestCase {
    private let decider = KeyEventDecider()

    func testEveryPresetConsumesAssignedSlotWithOnlySelectedPhysicalKey() {
        for preset in TriggerModifierPreset.allCases {
            let decision = decide(
                keyCode: KeyCodes.one,
                preset: preset,
                modifiers: modifiers(with: [preset.physicalKeyCode]),
                slots: snapshot(appCount: 1)
            )

            XCTAssertTrue(decision.consumesEvent, "\(preset.rawValue) should consume assigned slot")
            XCTAssertEqual(decision.label, preset.shortcutLabel(forShortcutIndex: 0))
        }
    }

    func testPairedNonSelectedSideAloneDoesNotMatch() {
        for preset in TriggerModifierPreset.allCases {
            let decision = decide(
                keyCode: KeyCodes.one,
                preset: preset,
                modifiers: modifiers(with: [pairedKeyCode(for: preset)]),
                slots: snapshot(appCount: 1)
            )

            XCTAssertFalse(decision.consumesEvent, "\(preset.rawValue) should require its selected side")
            XCTAssertNil(decision.intent)
        }
    }

    func testSelectedKeyPlusShiftRejectsForEveryPreset() {
        for preset in TriggerModifierPreset.allCases {
            for shiftKeyCode in [KeyCodes.leftShift, KeyCodes.rightShift] {
                let decision = decide(
                    keyCode: KeyCodes.one,
                    preset: preset,
                    modifiers: modifiers(with: [preset.physicalKeyCode, shiftKeyCode]),
                    slots: snapshot(appCount: 1)
                )

                XCTAssertFalse(decision.consumesEvent, "\(preset.rawValue) should reject shift key \(shiftKeyCode)")
                XCTAssertNil(decision.intent)
            }
        }
    }

    func testSelectedKeyPlusAnyNonSelectedOptionCommandControlRejectsForEveryPreset() {
        let optionCommandControlKeys = [
            KeyCodes.leftOption,
            KeyCodes.rightOption,
            KeyCodes.leftCommand,
            KeyCodes.rightCommand,
            KeyCodes.leftControl,
            KeyCodes.rightControl
        ]

        for preset in TriggerModifierPreset.allCases {
            for extraKeyCode in optionCommandControlKeys where extraKeyCode != preset.physicalKeyCode {
                let decision = decide(
                    keyCode: KeyCodes.one,
                    preset: preset,
                    modifiers: modifiers(with: [preset.physicalKeyCode, extraKeyCode]),
                    slots: snapshot(appCount: 1)
                )

                XCTAssertFalse(
                    decision.consumesEvent,
                    "\(preset.rawValue) should reject extra modifier \(KeyCodes.label(for: extraKeyCode))"
                )
                XCTAssertNil(decision.intent)
            }
        }
    }

    func testCapsLockAndFunctionDoNotRejectMatchesForEveryPreset() {
        for preset in TriggerModifierPreset.allCases {
            let decision = decide(
                keyCode: KeyCodes.one,
                preset: preset,
                modifiers: modifiers(with: [preset.physicalKeyCode, KeyCodes.capsLock, KeyCodes.function]),
                slots: snapshot(appCount: 1)
            )

            XCTAssertTrue(decision.consumesEvent, "\(preset.rawValue) should ignore caps lock and fn")
            XCTAssertEqual(decision.label, preset.shortcutLabel(forShortcutIndex: 0))
        }
    }

    func testDigitShortcutsConsumeOnlyAssignedSlots() {
        let snapshot = snapshot(appCount: 2)
        let one = decide(keyCode: KeyCodes.one, slots: snapshot)
        let two = decide(keyCode: KeyCodes.two, slots: snapshot)
        let three = decide(keyCode: KeyCodes.three, slots: snapshot)

        XCTAssertTrue(one.consumesEvent)
        XCTAssertTrue(two.consumesEvent)
        XCTAssertFalse(three.consumesEvent)
        XCTAssertEqual(three.result, .passThrough)
        XCTAssertNil(three.intent)
    }

    func testZeroTargetsTenthAssignedSlot() {
        let zero = decide(keyCode: KeyCodes.zero, slots: snapshot(appCount: 10))

        guard case .dockSlot(let target, let shortcutLabel) = zero.intent else {
            return XCTFail("expected tenth slot intent")
        }
        XCTAssertTrue(zero.consumesEvent)
        XCTAssertEqual(target.shortcutIndex, 9)
        XCTAssertEqual(shortcutLabel, "Left Option+0")
        XCTAssertEqual(target.displayName, "App10")
    }

    func testMissingAssignedSlotStillConsumesAndBindsTarget() {
        let store = DockSlotStore()
        store.replace(entries: [
            appEntry(name: "Missing App", dockOrdinal: 3, isMissing: true)
        ])

        let decision = decide(keyCode: KeyCodes.one, slots: store.snapshot())

        guard case .dockSlot(let target, _) = decision.intent else {
            return XCTFail("expected missing slot intent")
        }
        XCTAssertTrue(decision.consumesEvent)
        XCTAssertTrue(target.isMissing)
        XCTAssertEqual(target.shortcutIndex, 0)
        XCTAssertEqual(target.dockOrdinal, 3)
        XCTAssertEqual(target.displayName, "Missing App")
    }

    func testFinderBacktickUsesSelectedPreset() {
        for preset in TriggerModifierPreset.allCases {
            let decision = decide(
                keyCode: KeyCodes.backtick,
                preset: preset,
                modifiers: modifiers(with: [preset.physicalKeyCode]),
                slots: .empty
            )

            XCTAssertTrue(decision.consumesEvent)
            XCTAssertEqual(decision.intent, .finder(shortcutLabel: preset.shortcutLabel(forKeyLabel: "`")))
        }
    }

    func testRejectsWhenSelectedPresetKeyIsNotDown() {
        let decision = decider.decide(
            kind: .keyDown,
            keyCode: KeyCodes.one,
            modifiers: ModifierSnapshot(),
            triggerModifier: .leftOption,
            slots: snapshot(appCount: 1),
            windowActionsEnabled: false
        )

        XCTAssertFalse(decision.consumesEvent)
        XCTAssertNil(decision.intent)
    }

    func testKeyUpPassesThrough() {
        let decision = decider.decide(
            kind: .keyUp,
            keyCode: KeyCodes.one,
            modifiers: modifiers(with: [KeyCodes.leftOption]),
            triggerModifier: .leftOption,
            slots: snapshot(appCount: 1),
            windowActionsEnabled: false
        )

        XCTAssertFalse(decision.consumesEvent)
        XCTAssertEqual(decision.result, .passThrough)
        XCTAssertNil(decision.intent)
    }

    func testIntentBindsImmutableTargetAcrossRefresh() {
        let store = DockSlotStore()
        store.replace(entries: [
            appEntry(name: "Original", dockOrdinal: 1, bundleIdentifier: "dev.local.original")
        ])

        let originalDecision = decide(keyCode: KeyCodes.one, slots: store.snapshot())

        store.replace(entries: [
            appEntry(name: "Replacement", dockOrdinal: 1, bundleIdentifier: "dev.local.replacement")
        ])

        guard case .dockSlot(let originalTarget, _) = originalDecision.intent else {
            return XCTFail("expected original target")
        }
        guard case .dockSlot(let replacementTarget, _) = decide(keyCode: KeyCodes.one, slots: store.snapshot()).intent else {
            return XCTFail("expected replacement target")
        }

        XCTAssertEqual(originalTarget.displayName, "Original")
        XCTAssertEqual(originalTarget.bundleIdentifier, "dev.local.original")
        XCTAssertEqual(replacementTarget.displayName, "Replacement")
        XCTAssertEqual(replacementTarget.bundleIdentifier, "dev.local.replacement")
    }

    private func decide(
        keyCode: UInt16,
        preset: TriggerModifierPreset = .leftOption,
        modifiers: ModifierSnapshot? = nil,
        slots: DockSlotSnapshot
    ) -> KeyEventDecision {
        decider.decide(
            kind: .keyDown,
            keyCode: keyCode,
            modifiers: modifiers ?? self.modifiers(with: [preset.physicalKeyCode]),
            triggerModifier: preset,
            slots: slots,
            windowActionsEnabled: false
        )
    }

    private func snapshot(appCount: Int) -> DockSlotSnapshot {
        let store = DockSlotStore()
        store.replace(entries: (1...appCount).map { index in
            appEntry(name: "App\(index)", dockOrdinal: index)
        })
        return store.snapshot()
    }

    private func appEntry(
        name: String,
        dockOrdinal: Int,
        bundleIdentifier: String? = nil,
        isMissing: Bool = false
    ) -> DockAppEntry {
        DockAppEntry(
            dockOrdinal: dockOrdinal,
            appURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            displayName: name,
            bundleIdentifier: bundleIdentifier,
            isMissing: isMissing
        )
    }

    private func modifiers(with keyCodes: [UInt16]) -> ModifierSnapshot {
        var state = ModifierState()
        for keyCode in keyCodes {
            state.setPhysicalKey(keyCode, isDown: true)
        }
        return state.snapshot
    }

    private func pairedKeyCode(for preset: TriggerModifierPreset) -> UInt16 {
        switch preset {
        case .leftOption:
            KeyCodes.rightOption
        case .rightOption:
            KeyCodes.leftOption
        case .leftCommand:
            KeyCodes.rightCommand
        case .rightCommand:
            KeyCodes.leftCommand
        case .leftControl:
            KeyCodes.rightControl
        }
    }
}

private extension KeyEventDecision {
    var label: String? {
        intent?.label
    }
}
