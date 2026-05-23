import XCTest
@testable import DockTapProbe

final class RuleMatcherTests: XCTestCase {
    private let matcher = RuleMatcher()

    func testMatchesGlobalDigitRulesWithLeftOptionOnly() {
        var modifiers = ModifierSnapshot()
        modifiers.leftOption = true

        let digitRules: [(UInt16, String)] = [
            (KeyCodes.one, "1"),
            (KeyCodes.two, "2"),
            (KeyCodes.three, "3"),
            (KeyCodes.four, "4"),
            (KeyCodes.five, "5"),
            (KeyCodes.six, "6"),
            (KeyCodes.seven, "7"),
            (KeyCodes.eight, "8"),
            (KeyCodes.nine, "9"),
            (KeyCodes.zero, "0")
        ]

        for (keyCode, digit) in digitRules {
            XCTAssertEqual(
                matcher.matchKeyDown(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    frontmostBundleID: "com.apple.TextEdit"
                )?.id,
                "global.leftOption.\(digit)"
            )
        }
    }

    func testMatchesFinderBacktickOnlyWhenFinderIsFrontmost() {
        var modifiers = ModifierSnapshot()
        modifiers.leftOption = true

        XCTAssertEqual(
            matcher.matchKeyDown(
                keyCode: KeyCodes.backtick,
                modifiers: modifiers,
                frontmostBundleID: "com.apple.finder"
            )?.id,
            "finder.leftOption.backtick"
        )
        XCTAssertNil(
            matcher.matchKeyDown(
                keyCode: KeyCodes.backtick,
                modifiers: modifiers,
                frontmostBundleID: "com.apple.TextEdit"
            )
        )
    }

    func testRejectsWhenLeftOptionIsNotDown() {
        XCTAssertNil(
            matcher.matchKeyDown(
                keyCode: KeyCodes.one,
                modifiers: ModifierSnapshot(),
                frontmostBundleID: nil
            )
        )
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

            XCTAssertNil(
                matcher.matchKeyDown(
                    keyCode: KeyCodes.one,
                    modifiers: modifiers,
                    frontmostBundleID: nil
                ),
                "\(label) should reject the rule"
            )
        }
    }

    func testCapsLockAndFunctionDoNotRejectMatches() {
        var modifiers = ModifierSnapshot()
        modifiers.leftOption = true
        modifiers.capsLock = true
        modifiers.function = true

        XCTAssertEqual(
            matcher.matchKeyDown(
                keyCode: KeyCodes.one,
                modifiers: modifiers,
                frontmostBundleID: nil
            )?.id,
            "global.leftOption.1"
        )
    }

    func testKeyEventDecisionConsumesOnlyMatchingKeyDown() {
        let decider = KeyEventDecider()
        var modifiers = ModifierSnapshot()
        modifiers.leftOption = true

        let matchingDown = decider.decide(
            kind: .keyDown,
            keyCode: KeyCodes.one,
            modifiers: modifiers,
            frontmostBundleID: nil
        )
        XCTAssertTrue(matchingDown.consumesEvent)
        XCTAssertEqual(matchingDown.result, .consumed)
        XCTAssertEqual(matchingDown.match?.id, "global.leftOption.1")

        let matchingKeyUp = decider.decide(
            kind: .keyUp,
            keyCode: KeyCodes.one,
            modifiers: modifiers,
            frontmostBundleID: nil
        )
        XCTAssertFalse(matchingKeyUp.consumesEvent)
        XCTAssertEqual(matchingKeyUp.result, .passThrough)
        XCTAssertNil(matchingKeyUp.match)

        modifiers.leftOption = false
        let nonMatchingDown = decider.decide(
            kind: .keyDown,
            keyCode: KeyCodes.one,
            modifiers: modifiers,
            frontmostBundleID: nil
        )
        XCTAssertFalse(nonMatchingDown.consumesEvent)
        XCTAssertEqual(nonMatchingDown.result, .passThrough)
        XCTAssertNil(nonMatchingDown.match)
    }
}
