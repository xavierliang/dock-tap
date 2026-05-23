enum KeyEventKind {
    case keyDown
    case keyUp
}

struct KeyEventDecision: Equatable {
    let match: RuleMatch?
    let result: ProbeEventResult

    var consumesEvent: Bool {
        result == .consumed
    }
}

struct KeyEventDecider {
    private let matcher = RuleMatcher()

    func decide(
        kind: KeyEventKind,
        keyCode: UInt16,
        modifiers: ModifierSnapshot,
        frontmostBundleID: String?
    ) -> KeyEventDecision {
        guard kind == .keyDown else {
            return KeyEventDecision(match: nil, result: .passThrough)
        }

        let match = matcher.matchKeyDown(
            keyCode: keyCode,
            modifiers: modifiers,
            frontmostBundleID: frontmostBundleID
        )

        return KeyEventDecision(
            match: match,
            result: match == nil ? .passThrough : .consumed
        )
    }
}
