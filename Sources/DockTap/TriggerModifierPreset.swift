enum TriggerModifierPreset: String, CaseIterable, Equatable {
    case leftOption
    case leftCommand
    case leftControl
    case rightOption
    case rightCommand

    static let defaultPreset: TriggerModifierPreset = .leftOption

    var menuTitle: String {
        switch self {
        case .leftOption:
            "Left Option"
        case .leftCommand:
            "Left Command"
        case .leftControl:
            "Left Control"
        case .rightOption:
            "Right Option"
        case .rightCommand:
            "Right Command"
        }
    }

    var shortcutLabelPrefix: String {
        menuTitle
    }

    var physicalKeyCode: UInt16 {
        switch self {
        case .leftOption:
            KeyCodes.leftOption
        case .leftCommand:
            KeyCodes.leftCommand
        case .leftControl:
            KeyCodes.leftControl
        case .rightOption:
            KeyCodes.rightOption
        case .rightCommand:
            KeyCodes.rightCommand
        }
    }

    func shortcutLabel(forShortcutIndex shortcutIndex: Int) -> String {
        "\(shortcutLabelPrefix)+\(Self.digitLabel(forShortcutIndex: shortcutIndex))"
    }

    func shortcutLabel(forKeyLabel keyLabel: String) -> String {
        "\(shortcutLabelPrefix)+\(keyLabel)"
    }

    func selectedPhysicalKeyIsDown(in modifiers: ModifierSnapshot) -> Bool {
        modifiers.isPhysicalModifierDown(physicalKeyCode)
    }

    func matches(_ modifiers: ModifierSnapshot) -> Bool {
        guard selectedPhysicalKeyIsDown(in: modifiers) else {
            return false
        }
        guard !modifiers.leftShift, !modifiers.rightShift else {
            return false
        }

        return Self.rejectingOptionCommandControlKeyCodes(for: self).allSatisfy {
            !modifiers.isPhysicalModifierDown($0)
        }
    }

    private static func digitLabel(forShortcutIndex shortcutIndex: Int) -> String {
        switch shortcutIndex {
        case 0...8:
            "\(shortcutIndex + 1)"
        case 9:
            "0"
        default:
            "?"
        }
    }

    private static func rejectingOptionCommandControlKeyCodes(for preset: TriggerModifierPreset) -> [UInt16] {
        [
            KeyCodes.leftOption,
            KeyCodes.rightOption,
            KeyCodes.leftCommand,
            KeyCodes.rightCommand,
            KeyCodes.leftControl,
            KeyCodes.rightControl
        ].filter { $0 != preset.physicalKeyCode }
    }
}
