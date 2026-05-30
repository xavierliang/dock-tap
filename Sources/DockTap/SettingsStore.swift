import Foundation

final class SettingsStore {
    private enum Keys {
        static let triggerModifierPreset = "triggerModifierPreset"
        static let windowActionsEnabled = "windowActionsEnabled"
        static let hasSeenClosedLidWarning = "hasSeenClosedLidWarning"
        static let dimInternalDisplayOnLidClose = "dimInternalDisplayOnLidClose"
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

    /// 合盖时是否自动把内置屏调暗（开盖恢复）。默认开启；
    /// `defaults.bool` 未设置时返回 false，故用 object 判定以便缺省回落到 true。
    var dimInternalDisplayOnLidClose: Bool {
        get {
            defaults.object(forKey: Keys.dimInternalDisplayOnLidClose) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.dimInternalDisplayOnLidClose)
        }
    }
}
