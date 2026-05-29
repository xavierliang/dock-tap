import Foundation

enum AppText {
    enum Status {
        static let ready = NSLocalizedString(
            "status.ready", value: "Ready", comment: "Status line: event tap is ready")
        static let starting = NSLocalizedString(
            "status.starting", value: "Starting", comment: "Status line: starting up")
        static let missingAccessibilityPermission = NSLocalizedString(
            "status.missingAccessibilityPermission",
            value: "Missing Accessibility Permission",
            comment: "Status line: accessibility permission not granted")
    }

    enum DockShortcuts {
        static let finder = NSLocalizedString(
            "dockShortcuts.finder", value: "Finder", comment: "Name of the macOS Finder app")
        static let unassigned = NSLocalizedString(
            "dockShortcuts.unassigned", value: "Unassigned",
            comment: "A dock shortcut slot with no app assigned")

        static func countTitle(_ count: Int) -> String {
            let format = count == 1
                ? NSLocalizedString(
                    "dockShortcuts.count.one", value: "%d Dock shortcut",
                    comment: "Count of assigned dock shortcuts, singular")
                : NSLocalizedString(
                    "dockShortcuts.count.other", value: "%d Dock shortcuts",
                    comment: "Count of assigned dock shortcuts, plural")
            return String(format: format, count)
        }
    }

    enum Menu {
        static let dockShortcuts = NSLocalizedString(
            "menu.dockShortcuts", value: "Dock Shortcuts", comment: "Menu section header")
        static let triggerModifier = NSLocalizedString(
            "menu.triggerModifier", value: "Trigger Modifier", comment: "Menu: trigger modifier label")
        static let updateDockShortcuts = NSLocalizedString(
            "menu.updateDockShortcuts", value: "Update Dock Shortcuts", comment: "Menu command")
        static let showLogs = NSLocalizedString(
            "menu.showLogs", value: "Show Logs", comment: "Menu command")
        static let checkAccessibility = NSLocalizedString(
            "menu.checkAccessibility", value: "Check Accessibility", comment: "Menu command")
        static let openAccessibilitySettings = NSLocalizedString(
            "menu.openAccessibilitySettings", value: "Open Accessibility Settings",
            comment: "Menu command")
        static let checkForUpdates = NSLocalizedString(
            "menu.checkForUpdates", value: "Check for Updates…", comment: "Menu command")
        static let quit = NSLocalizedString(
            "menu.quit", value: "Quit", comment: "Menu command")

        static func triggerModifierTitle(_ presetTitle: String) -> String {
            String(
                format: NSLocalizedString(
                    "menu.triggerModifierFormat", value: "Trigger Modifier: %@",
                    comment: "Menu: trigger modifier with selected preset name (preset kept in English)"),
                presetTitle)
        }

        static func versionTitle(version: String) -> String {
            String(
                format: NSLocalizedString(
                    "menu.versionFormat", value: "Version %@", comment: "Menu: app version"),
                version)
        }

        static func updateAvailable(version: String) -> String {
            String(
                format: NSLocalizedString(
                    "menu.updateAvailableFormat", value: "Update Available: v%@",
                    comment: "Menu: an update is available"),
                version)
        }
    }

    enum WindowSnap {
        static let toggleTitle = NSLocalizedString(
            "windowSnap.toggle", value: "Enable Window Snap", comment: "Menu toggle")
        static let submenuTitle = NSLocalizedString(
            "windowSnap.submenu", value: "Window Snap Bindings", comment: "Submenu title")
        static let leftHalf = NSLocalizedString(
            "windowSnap.leftHalf", value: "Left Half", comment: "Window snap action")
        static let rightHalf = NSLocalizedString(
            "windowSnap.rightHalf", value: "Right Half", comment: "Window snap action")
        static let topHalf = NSLocalizedString(
            "windowSnap.topHalf", value: "Top Half", comment: "Window snap action")
        static let bottomHalf = NSLocalizedString(
            "windowSnap.bottomHalf", value: "Bottom Half", comment: "Window snap action")
        static let maximize = NSLocalizedString(
            "windowSnap.maximize", value: "Maximize", comment: "Window snap action")
        static let center = NSLocalizedString(
            "windowSnap.center", value: "Center", comment: "Window snap action")
    }

    enum LoginItem {
        static let launchAtLogin = NSLocalizedString(
            "loginItem.launchAtLogin", value: "Launch at Login", comment: "Menu toggle")
        static let requiresApproval = NSLocalizedString(
            "loginItem.requiresApproval", value: "Launch at Login (Requires Approval)",
            comment: "Login item status")
        static let notFound = NSLocalizedString(
            "loginItem.notFound", value: "Launch at Login (Not Found)", comment: "Login item status")
        static let statusError = NSLocalizedString(
            "loginItem.statusError", value: "Launch at Login (Status Error)",
            comment: "Login item status")
        static let approveHint = NSLocalizedString(
            "loginItem.approveHint", value: "Approve in System Settings > General > Login Items",
            comment: "Hint for approving the login item")
        static let failureHint = NSLocalizedString(
            "loginItem.failureHint", value: "Launch at Login change failed",
            comment: "Login item change failure")
    }

    enum LogWindow {
        static let title = NSLocalizedString(
            "logWindow.title", value: "Dock Tap Logs", comment: "Log window title")
    }
}
