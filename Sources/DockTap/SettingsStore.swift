import Foundation

final class SettingsStore {
    private enum Keys {
        static let triggerModifierPreset = "triggerModifierPreset"
        static let windowActionsEnabled = "windowActionsEnabled"
        static let hasSeenClosedLidWarning = "hasSeenClosedLidWarning"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedTriggerModifierPreset: TriggerModifierPreset {
        get {
            guard let rawValue = defaults.string(forKey: Keys.triggerModifierPreset) else {
                return .defaultPreset
            }
            return TriggerModifierPreset(rawValue: rawValue) ?? .defaultPreset
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.triggerModifierPreset)
        }
    }

    var windowActionsEnabled: Bool {
        get {
            defaults.bool(forKey: Keys.windowActionsEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.windowActionsEnabled)
        }
    }

    var hasSeenClosedLidWarning: Bool {
        get {
            defaults.bool(forKey: Keys.hasSeenClosedLidWarning)
        }
        set {
            defaults.set(newValue, forKey: Keys.hasSeenClosedLidWarning)
        }
    }
}
