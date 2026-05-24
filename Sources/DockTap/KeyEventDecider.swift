enum KeyEventKind {
    case keyDown
    case keyUp
}

struct KeyEventDecision: Equatable {
    let intent: ShortcutIntent?
    let result: ShortcutDecisionResult

    var consumesEvent: Bool {
        result == .consumed
    }
}

enum ShortcutDecisionResult: String, Equatable {
    case consumed
    case passThrough = "pass-through"
}

struct KeyEventDecider {
    private let matcher = RuleMatcher()

    func decide(
        kind: KeyEventKind,
        keyCode: UInt16,
        modifiers: ModifierSnapshot,
        triggerModifier: TriggerModifierPreset,
        slots: DockSlotSnapshot
    ) -> KeyEventDecision {
        guard kind == .keyDown else {
            return KeyEventDecision(intent: nil, result: .passThrough)
        }

        let intent = matcher.matchKeyDown(
            keyCode: keyCode,
            modifiers: modifiers,
            triggerModifier: triggerModifier,
            slots: slots
        )

        return KeyEventDecision(
            intent: intent,
            result: intent == nil ? .passThrough : .consumed
        )
    }
}
