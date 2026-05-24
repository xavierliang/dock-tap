import XCTest
@testable import DockTap

final class RuleMatcherTests: XCTestCase {
    private let decider = KeyEventDecider()

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

        guard case .dockSlot(let target) = zero.intent else {
            return XCTFail("expected tenth slot intent")
        }
        XCTAssertTrue(zero.consumesEvent)
        XCTAssertEqual(target.shortcutIndex, 9)
        XCTAssertEqual(target.shortcutLabel, "leftOption+0")
        XCTAssertEqual(target.displayName, "App10")
    }

    func testMissingAssignedSlotStillConsumesAndBindsTarget() {
        let store = DockSlotStore()
        store.replace(entries: [
            appEntry(name: "Missing App", dockOrdinal: 3, isMissing: true)
        ])

        let decision = decide(keyCode: KeyCodes.one, slots: store.snapshot())

        guard case .dockSlot(let target) = decision.intent else {
            return XCTFail("expected missing slot intent")
        }
        XCTAssertTrue(decision.consumesEvent)
        XCTAssertTrue(target.isMissing)
        XCTAssertEqual(target.shortcutIndex, 0)
        XCTAssertEqual(target.dockOrdinal, 3)
        XCTAssertEqual(target.displayName, "Missing App")
    }

    func testFinderBacktickIsGlobal() {
        let decision = decide(keyCode: KeyCodes.backtick, slots: .empty)

        XCTAssertTrue(decision.consumesEvent)
        XCTAssertEqual(decision.intent, .finder)
    }

    func testRejectsWhenLeftOptionIsNotDown() {
        let decision = decider.decide(
            kind: .keyDown,
            keyCode: KeyCodes.one,
            modifiers: ModifierSnapshot(),
            slots: snapshot(appCount: 1)
        )

        XCTAssertFalse(decision.consumesEvent)
        XCTAssertNil(decision.intent)
    }

    func testRejectsRightOptionShiftCommandAndControlExtras() {
        let extraModifiers: [(WritableKeyPath<ModifierSnapshot, Bool>, StaticString)] = [
            (\.rightOption, "rightOption"),
            (\.leftShift, "leftShift"),
            (\.rightShift, "rightShift"),
            (\.leftCommand, "leftCommand"),
            (\.rightCommand, "rightCommand"),
            (\.leftControl, "leftControl"),
            (\.rightControl, "rightControl")
        ]

        for (keyPath, label) in extraModifiers {
            var modifiers = ModifierSnapshot()
            modifiers.leftOption = true
            modifiers[keyPath: keyPath] = true

            let decision = decider.decide(
                kind: .keyDown,
                keyCode: KeyCodes.one,
                modifiers: modifiers,
                slots: snapshot(appCount: 1)
            )

            XCTAssertFalse(decision.consumesEvent, "\(label) should reject the shortcut")
            XCTAssertNil(decision.intent)
        }
    }

    func testCapsLockAndFunctionDoNotRejectMatches() {
        var modifiers = ModifierSnapshot()
        modifiers.leftOption = true
        modifiers.capsLock = true
        modifiers.function = true

        let decision = decider.decide(
            kind: .keyDown,
            keyCode: KeyCodes.one,
            modifiers: modifiers,
            slots: snapshot(appCount: 1)
        )

        XCTAssertTrue(decision.consumesEvent)
        XCTAssertNotNil(decision.intent)
    }

    func testKeyUpPassesThrough() {
        let decision = decider.decide(
            kind: .keyUp,
            keyCode: KeyCodes.one,
            modifiers: leftOptionModifiers(),
            slots: snapshot(appCount: 1)
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

        guard case .dockSlot(let originalTarget) = originalDecision.intent else {
            return XCTFail("expected original target")
        }
        guard case .dockSlot(let replacementTarget) = decide(keyCode: KeyCodes.one, slots: store.snapshot()).intent else {
            return XCTFail("expected replacement target")
        }

        XCTAssertEqual(originalTarget.displayName, "Original")
        XCTAssertEqual(originalTarget.bundleIdentifier, "dev.local.original")
        XCTAssertEqual(replacementTarget.displayName, "Replacement")
        XCTAssertEqual(replacementTarget.bundleIdentifier, "dev.local.replacement")
    }

    private func decide(keyCode: UInt16, slots: DockSlotSnapshot) -> KeyEventDecision {
        decider.decide(
            kind: .keyDown,
            keyCode: keyCode,
            modifiers: leftOptionModifiers(),
            slots: slots
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

    private func leftOptionModifiers() -> ModifierSnapshot {
        var modifiers = ModifierSnapshot()
        modifiers.leftOption = true
        return modifiers
    }
}
