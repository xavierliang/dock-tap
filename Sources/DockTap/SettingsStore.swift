import Foundation

final class SettingsStore {
    private enum Keys {
        static let triggerModifierPreset = "triggerModifierPreset"
        static let dockShortcutsEnabled = "dockShortcutsEnabled"
        static let windowActionsEnabled = "windowActionsEnabled"
        static let hasSeenClosedLidWarning = "hasSeenClosedLidWarning"
        static let shouldResumeClosedLidIndefinitely = "shouldResumeClosedLidIndefinitely"
        static let keepDisplayAwakeDuringSession = "keepDisplayAwakeDuringSession"
    }

    private let defaults: UserDefaults

    /// Opt-in display idle-sleep prevention, scoped to a keep-awake session.
    var keepDisplayAwakeDuringSession: Bool {
        get { defaults.bool(forKey: Keys.keepDisplayAwakeDuringSession) }
        set { defaults.set(newValue, forKey: Keys.keepDisplayAwakeDuringSession) }
    }

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

    var dockShortcutsEnabled: Bool {
        get {
            guard defaults.object(forKey: Keys.dockShortcutsEnabled) != nil else {
                return true
            }
            return defaults.bool(forKey: Keys.dockShortcutsEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.dockShortcutsEnabled)
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

    /// User chose Enable Indefinitely; restore that mode after Dock Tap (or the Mac) restarts.
    /// Cleared by Stop Now or by starting a timed session. Not cleared on quit/update.
    var shouldResumeClosedLidIndefinitely: Bool {
        get {
            defaults.bool(forKey: Keys.shouldResumeClosedLidIndefinitely)
        }
        set {
            defaults.set(newValue, forKey: Keys.shouldResumeClosedLidIndefinitely)
        }
    }
}
