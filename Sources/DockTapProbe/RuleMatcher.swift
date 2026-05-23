import Foundation

struct RuleMatch: Equatable {
    let id: String
    let label: String
}

struct RuleMatcher {
    static let finderBundleID = "com.apple.finder"

    private let digitRules: [UInt16: String] = [
        KeyCodes.one: "1",
        KeyCodes.two: "2",
        KeyCodes.three: "3",
        KeyCodes.four: "4",
        KeyCodes.five: "5",
        KeyCodes.six: "6",
        KeyCodes.seven: "7",
        KeyCodes.eight: "8",
        KeyCodes.nine: "9",
        KeyCodes.zero: "0"
    ]

    func matchKeyDown(
        keyCode: UInt16,
        modifiers: ModifierSnapshot,
        frontmostBundleID: String?
    ) -> RuleMatch? {
        guard modifiers.leftOption, !modifiers.hasRejectingExtraModifier else {
            return nil
        }

        if let digit = digitRules[keyCode] {
            return RuleMatch(
                id: "global.leftOption.\(digit)",
                label: "leftOption+\(digit)"
            )
        }

        if keyCode == KeyCodes.backtick, frontmostBundleID == Self.finderBundleID {
            return RuleMatch(
                id: "finder.leftOption.backtick",
                label: "Finder leftOption+`"
            )
        }

        return nil
    }
}
