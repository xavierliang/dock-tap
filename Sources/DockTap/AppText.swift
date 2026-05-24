enum AppText {
    enum Status {
        static let ready = "Ready"
        static let missingAccessibilityPermission = "Missing Accessibility Permission"
    }

    enum DockShortcuts {
        static let firstDockApp = "First Dock app"
        static let secondDockApp = "Second Dock app"
        static let tenthDockApp = "Tenth Dock app"
        static let finder = "Finder"
        static let unassigned = "Unassigned"

        static func countTitle(_ count: Int) -> String {
            count == 1 ? "1 Dock shortcut" : "\(count) Dock shortcuts"
        }
    }

    enum Menu {
        static let showDockMapping = "Show Dock Mapping"
        static let triggerModifier = "Trigger Modifier"
        static let updateDockShortcuts = "Update Dock Shortcuts"
        static let showLogs = "Show Logs"
        static let checkAccessibility = "Check Accessibility"
        static let openAccessibilitySettings = "Open Accessibility Settings"
        static let quit = "Quit"

        static func triggerModifierTitle(_ presetTitle: String) -> String {
            "\(triggerModifier): \(presetTitle)"
        }
    }

    enum LoginItem {
        static let launchAtLogin = "Launch at Login"
        static let requiresApproval = "Launch at Login (Requires Approval)"
        static let notFound = "Launch at Login (Not Found)"
        static let statusError = "Launch at Login (Status Error)"
        static let approveHint = "Approve in System Settings > General > Login Items"
        static let failureHint = "Launch at Login change failed"
    }
}
