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

    private let windowActionsByKeyCode: [UInt16: WindowAction] = [
        KeyCodes.leftArrow: .leftHalf,
        KeyCodes.rightArrow: .rightHalf,
        KeyCodes.upArrow: .topHalf,
        KeyCodes.downArrow: .bottomHalf,
        KeyCodes.returnKey: .maximize,
        KeyCodes.space: .center
    ]

    private let keepAwakeShortcutsByKeyCode: [UInt16: KeepAwakeShortcut] = [
        KeyCodes.a: .oneHour,
        KeyCodes.s: .indefinite,
        KeyCodes.d: .stop
    ]

    func matchKeyDown(
        keyCode: UInt16,
        modifiers: ModifierSnapshot,
        triggerModifier: TriggerModifierPreset,
        slots: DockSlotSnapshot,
        dockShortcutsEnabled: Bool,
        windowActionsEnabled: Bool
    ) -> ShortcutIntent? {
        guard triggerModifier.matches(modifiers) else {
            return nil
        }

        if dockShortcutsEnabled {
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
        }

        if windowActionsEnabled, let action = windowActionsByKeyCode[keyCode] {
            return .windowAction(
                action,
                shortcutLabel: triggerModifier.shortcutLabel(forKeyLabel: action.shortcutKeyLabel)
            )
        }

        if let action = keepAwakeShortcutsByKeyCode[keyCode] {
            return .keepAwake(
                action,
                shortcutLabel: triggerModifier.shortcutLabel(forKeyLabel: action.shortcutKeyLabel)
            )
        }

        return nil
    }
}
