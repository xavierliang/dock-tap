import Foundation

struct RuleMatcher {
    private let digitShortcutIndexes: [UInt16: Int] = [
        KeyCodes.one: 0,
        KeyCodes.two: 1,
        KeyCodes.three: 2,
        KeyCodes.four: 3,
        KeyCodes.five: 4,
        KeyCodes.six: 5,
        KeyCodes.seven: 6,
        KeyCodes.eight: 7,
        KeyCodes.nine: 8,
        KeyCodes.zero: 9
    ]

    func matchKeyDown(
        keyCode: UInt16,
        modifiers: ModifierSnapshot,
        triggerModifier: TriggerModifierPreset,
        slots: DockSlotSnapshot
    ) -> ShortcutIntent? {
        guard triggerModifier.matches(modifiers) else {
            return nil
        }

        if let shortcutIndex = digitShortcutIndexes[keyCode] {
            guard let target = slots.target(shortcutIndex: shortcutIndex) else {
                return nil
            }
            return .dockSlot(
                target,
                shortcutLabel: triggerModifier.shortcutLabel(forShortcutIndex: shortcutIndex)
            )
        }

        if keyCode == KeyCodes.backtick {
            return .finder(shortcutLabel: triggerModifier.shortcutLabel(forKeyLabel: "`"))
        }

        return nil
    }
}
