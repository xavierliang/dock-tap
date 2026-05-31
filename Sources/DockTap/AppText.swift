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
        static let enableDockShortcuts = NSLocalizedString(
            "menu.enableDockShortcuts", value: "Enable Dock Shortcuts", comment: "Menu toggle")
        static let dockShortcutBindings = NSLocalizedString(
            "menu.dockShortcutBindings", value: "Dock Shortcut Bindings", comment: "Submenu title")
        static let triggerModifier = NSLocalizedString(
            "menu.triggerModifier", value: "Shortcut Modifier", comment: "Menu: shortcut modifier label")
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
                    "menu.triggerModifierFormat", value: "Shortcut Modifier: %@",
                    comment: "Menu: shortcut modifier with selected preset name (preset kept in English)"),
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

    enum ClosedLid {
        static let submenuTitle = NSLocalizedString(
            "closedLid.submenu", value: "Closed-Lid Keep Awake", comment: "Menu submenu title")
        static let off = NSLocalizedString(
            "closedLid.status.off", value: "Off", comment: "Closed-lid keep-awake status")
        static let starting = NSLocalizedString(
            "closedLid.status.starting", value: "Starting…", comment: "Closed-lid keep-awake status")
        static let stopping = NSLocalizedString(
            "closedLid.status.stopping", value: "Stopping…", comment: "Closed-lid keep-awake status")
        static let onIndefinitely = NSLocalizedString(
            "closedLid.status.onIndefinitely", value: "On indefinitely",
            comment: "Closed-lid keep-awake status")
        static let helperApprovalRequired = NSLocalizedString(
            "closedLid.status.helperApprovalRequired", value: "Helper approval required",
            comment: "Closed-lid keep-awake status")
        static let helperApprovalBody = NSLocalizedString(
            "closedLid.helperApproval.body",
            value: "Approve Dock Tap Closed-Lid Helper in System Settings > General > Login Items & Extensions.",
            comment: "Closed-lid helper approval guidance")
        static let enableOneHour = NSLocalizedString(
            "closedLid.enableOneHour", value: "Enable for 1 Hour", comment: "Closed-lid menu command")
        static let enableIndefinitely = NSLocalizedString(
            "closedLid.enableIndefinitely", value: "Enable Indefinitely",
            comment: "Closed-lid menu command")
        static let stopNow = NSLocalizedString(
            "closedLid.stopNow", value: "Stop Now", comment: "Closed-lid menu command")
        static let openLoginItemsSettings = NSLocalizedString(
            "closedLid.openLoginItemsSettings", value: "Open Login Items Settings...",
            comment: "Closed-lid menu command")
        static let warningTitle = NSLocalizedString(
            "closedLid.warning.title", value: "Enable Closed-Lid Keep Awake?",
            comment: "Closed-lid first-use warning title")
        static let warningBody = NSLocalizedString(
            "closedLid.warning.body",
            value: "This changes your Mac's normal lid-sleep behavior by setting pmset disablesleep. It can increase battery drain and heat. Use it only on a ventilated surface, and stop it any time from the Dock Tap menu.",
            comment: "Closed-lid first-use warning body")
        static let warningContinue = NSLocalizedString(
            "closedLid.warning.continue", value: "Continue", comment: "Closed-lid warning button")
        static let warningCancel = NSLocalizedString(
            "closedLid.warning.cancel", value: "Cancel", comment: "Closed-lid warning button")
        static let stopFailureTitle = NSLocalizedString(
            "closedLid.stopFailure.title", value: "Closed-Lid Keep Awake Could Not Stop",
            comment: "Closed-lid stop failure alert title")
        static let manualRecovery = NSLocalizedString(
            "closedLid.manualRecovery", value: "Run sudo pmset -a disablesleep 0 to restore normal lid sleep.",
            comment: "Closed-lid manual recovery guidance")
        static let updateBlockedTitle = NSLocalizedString(
            "closedLid.updateBlocked.title", value: "Update Blocked",
            comment: "Closed-lid Sparkle update block title")
        static let updateBlockedBody = NSLocalizedString(
            "closedLid.updateBlocked.body",
            value: "Dock Tap could not confirm that closed-lid keep awake was stopped, so the update was not installed.",
            comment: "Closed-lid Sparkle update block body")

        static func statusTitle(for state: ClosedLidKeepAwakeState) -> String {
            switch state {
            case .off:
                return off
            case .starting:
                return starting
            case .activeTimed(let endDate):
                return onUntil(time: DateFormatter.localizedString(from: endDate, dateStyle: .none, timeStyle: .short))
            case .activeIndefinite:
                return onIndefinitely
            case .stopping:
                return stopping
            case .requiresApproval:
                return helperApprovalRequired
            case .error(let message):
                return error(message)
            case .errorWithActiveSession(let message):
                return stopFailed(message)
            case .stopFailed(let message):
                return stopFailed(message)
            }
        }

        static func onUntil(time: String) -> String {
            String(
                format: NSLocalizedString(
                    "closedLid.status.onUntil", value: "On until %@",
                    comment: "Closed-lid timed keep-awake status"),
                time)
        }

        static func error(_ message: String) -> String {
            String(
                format: NSLocalizedString(
                    "closedLid.status.error", value: "Error: %@",
                    comment: "Closed-lid helper error status"),
                shortMessage(message))
        }

        static func stopFailed(_ message: String) -> String {
            String(
                format: NSLocalizedString(
                    "closedLid.status.stopFailed", value: "Error: %@. %@",
                    comment: "Closed-lid stop failure status"),
                shortMessage(message),
                manualRecovery)
        }

        static func stopFailureBody(_ message: String) -> String {
            String(
                format: NSLocalizedString(
                    "closedLid.stopFailure.body", value: "%@\n\n%@",
                    comment: "Closed-lid stop failure alert body"),
                shortMessage(message),
                manualRecovery)
        }

        private static func shortMessage(_ message: String) -> String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 90 else {
                return trimmed.isEmpty ? NSLocalizedString(
                    "closedLid.error.unknown", value: "Unknown error",
                    comment: "Closed-lid fallback error") : trimmed
            }
            return "\(trimmed.prefix(87))..."
        }
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
