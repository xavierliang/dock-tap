import Foundation

struct MenuContentModel: Equatable {
    struct ClosedLidMenu: Equatable {
        let title: String
        let statusTitle: String
        let enableOneHourTitle: String
        let enableOneHourIsEnabled: Bool
        let enableOneHourIsChecked: Bool
        let enableIndefinitelyTitle: String
        let enableIndefinitelyIsEnabled: Bool
        let enableIndefinitelyIsChecked: Bool
        let stopNowTitle: String
        let stopNowIsEnabled: Bool
        let openApprovalSettingsTitle: String?
    }

    struct MappingRow: Equatable {
        let shortcutIndex: Int
        let title: String
        let isAssigned: Bool
    }

    struct TriggerRow: Equatable {
        let preset: TriggerModifierPreset
        let title: String
        let isSelected: Bool
    }

    struct WindowSnapRow: Equatable {
        let action: WindowAction
        let title: String
    }

    let summaryTitle: String
    let dockShortcutsTitle: String
    let finderShortcutTitle: String
    let mappingRows: [MappingRow]
    let triggerModifierTitle: String
    let triggerRows: [TriggerRow]
    let windowSnapToggleTitle: String
    let windowSnapToggleIsOn: Bool
    let windowSnapSubmenuTitle: String
    let windowSnapRows: [WindowSnapRow]
    let closedLidMenu: ClosedLidMenu
    let updateDockShortcutsTitle: String
    let showLogsTitle: String
    let checkAccessibilityTitle: String?
    let openAccessibilitySettingsTitle: String?
    let updateAvailableTitle: String?
    let checkForUpdatesTitle: String
    let versionTitle: String
    let quitTitle: String
    let assignedShortcutCount: Int

    init(
        dockRows: [DockSlotMenuRow],
        selectedPreset: TriggerModifierPreset,
        isAccessibilityTrusted: Bool,
        isEventTapReady: Bool,
        windowActionsEnabled: Bool,
        closedLidState: ClosedLidKeepAwakeState = .off,
        appName: String,
        appVersion: String,
        availableUpdateVersion: String? = nil
    ) {
        let rowsByIndex = Dictionary(uniqueKeysWithValues: dockRows.map { ($0.target.shortcutIndex, $0) })
        let assignedCount = min(10, Set(rowsByIndex.keys.filter { (0..<10).contains($0) }).count)
        let statusTitle = Self.statusTitle(
            isAccessibilityTrusted: isAccessibilityTrusted,
            isEventTapReady: isEventTapReady
        )

        summaryTitle = [
            statusTitle,
            selectedPreset.menuTitle,
            AppText.DockShortcuts.countTitle(assignedCount)
        ].joined(separator: " · ")
        assignedShortcutCount = assignedCount
        dockShortcutsTitle = AppText.Menu.dockShortcuts
        finderShortcutTitle = Self.finderShortcutTitle(selectedPreset: selectedPreset)
        mappingRows = (0..<10).map { shortcutIndex in
            Self.mappingRow(
                shortcutIndex: shortcutIndex,
                row: rowsByIndex[shortcutIndex],
                selectedPreset: selectedPreset
            )
        }
        triggerModifierTitle = AppText.Menu.triggerModifierTitle(selectedPreset.menuTitle)
        triggerRows = TriggerModifierPreset.allCases.map { preset in
            TriggerRow(
                preset: preset,
                title: preset.menuTitle,
                isSelected: preset == selectedPreset
            )
        }
        windowSnapToggleTitle = AppText.WindowSnap.toggleTitle
        windowSnapToggleIsOn = windowActionsEnabled
        windowSnapSubmenuTitle = AppText.WindowSnap.submenuTitle
        windowSnapRows = Self.windowSnapRows(selectedPreset: selectedPreset)
        closedLidMenu = Self.closedLidMenu(state: closedLidState)
        updateDockShortcutsTitle = AppText.Menu.updateDockShortcuts
        showLogsTitle = AppText.Menu.showLogs
        checkAccessibilityTitle = isAccessibilityTrusted ? nil : AppText.Menu.checkAccessibility
        openAccessibilitySettingsTitle = isAccessibilityTrusted ? nil : AppText.Menu.openAccessibilitySettings
        updateAvailableTitle = availableUpdateVersion.map { AppText.Menu.updateAvailable(version: $0) }
        checkForUpdatesTitle = AppText.Menu.checkForUpdates
        versionTitle = AppText.Menu.versionTitle(version: appVersion)
        quitTitle = AppText.Menu.quit
    }

    private static func statusTitle(isAccessibilityTrusted: Bool, isEventTapReady: Bool) -> String {
        guard isAccessibilityTrusted else {
            return AppText.Status.missingAccessibilityPermission
        }
        guard isEventTapReady else {
            return AppText.Status.starting
        }
        return AppText.Status.ready
    }

    private static func finderShortcutTitle(selectedPreset: TriggerModifierPreset) -> String {
        "\(selectedPreset.shortcutLabel(forKeyLabel: "`"))  \(AppText.DockShortcuts.finder)"
    }

    private static func mappingRow(
        shortcutIndex: Int,
        row: DockSlotMenuRow?,
        selectedPreset: TriggerModifierPreset
    ) -> MappingRow {
        let label = selectedPreset.shortcutLabel(forShortcutIndex: shortcutIndex)
        guard let row else {
            return MappingRow(
                shortcutIndex: shortcutIndex,
                title: "\(label)  \(AppText.DockShortcuts.unassigned)",
                isAssigned: false
            )
        }

        return MappingRow(
            shortcutIndex: shortcutIndex,
            title: "\(label)  \(row.target.displayName) [\(row.status.rawValue)]",
            isAssigned: true
        )
    }

    private static func windowSnapRows(selectedPreset: TriggerModifierPreset) -> [WindowSnapRow] {
        WindowAction.allCases.map { action in
            WindowSnapRow(
                action: action,
                title: "\(selectedPreset.shortcutLabel(forKeyLabel: action.shortcutKeyLabel))  \(action.displayName)"
            )
        }
    }

    private static func closedLidMenu(state: ClosedLidKeepAwakeState) -> ClosedLidMenu {
        let enableCommandsAreEnabled = state.canStartSession
        return ClosedLidMenu(
            title: AppText.ClosedLid.submenuTitle,
            statusTitle: AppText.ClosedLid.statusTitle(for: state),
            enableOneHourTitle: AppText.ClosedLid.enableOneHour,
            enableOneHourIsEnabled: enableCommandsAreEnabled,
            enableOneHourIsChecked: state.isTimed,
            enableIndefinitelyTitle: AppText.ClosedLid.enableIndefinitely,
            enableIndefinitelyIsEnabled: enableCommandsAreEnabled,
            enableIndefinitelyIsChecked: state.isIndefinite,
            stopNowTitle: AppText.ClosedLid.stopNow,
            stopNowIsEnabled: state.canStopSession,
            openApprovalSettingsTitle: state == .requiresApproval ? AppText.ClosedLid.openLoginItemsSettings : nil
        )
    }
}

enum ClosedLidKeepAwakeState: Equatable {
    case off
    case starting
    case activeTimed(endDate: Date)
    case activeIndefinite
    case stopping
    case requiresApproval
    case error(String)
    case errorWithActiveSession(String)
    case stopFailed(String)

    var canStartSession: Bool {
        switch self {
        case .off, .error:
            return true
        case .starting, .activeTimed, .activeIndefinite, .stopping, .requiresApproval, .errorWithActiveSession, .stopFailed:
            return false
        }
    }

    var canStopSession: Bool {
        switch self {
        case .activeTimed, .activeIndefinite, .starting, .errorWithActiveSession, .stopFailed:
            return true
        case .off, .stopping, .requiresApproval, .error:
            return false
        }
    }

    var isActive: Bool {
        switch self {
        case .activeTimed, .activeIndefinite:
            return true
        case .off, .starting, .stopping, .requiresApproval, .error, .errorWithActiveSession, .stopFailed:
            return false
        }
    }

    var isTimed: Bool {
        if case .activeTimed = self {
            return true
        }
        return false
    }

    var isIndefinite: Bool {
        self == .activeIndefinite
    }
}
