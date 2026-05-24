struct MenuContentModel: Equatable {
    struct ExampleRow: Equatable {
        let title: String
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

    let summaryTitle: String
    let exampleRows: [ExampleRow]
    let showDockMappingTitle: String
    let mappingRows: [MappingRow]
    let triggerModifierTitle: String
    let triggerRows: [TriggerRow]
    let updateDockShortcutsTitle: String
    let showLogsTitle: String
    let checkAccessibilityTitle: String?
    let openAccessibilitySettingsTitle: String?
    let quitTitle: String
    let assignedShortcutCount: Int

    init(
        dockRows: [DockSlotMenuRow],
        selectedPreset: TriggerModifierPreset,
        isAccessibilityTrusted: Bool,
        isEventTapReady: Bool
    ) {
        let rowsByIndex = Dictionary(uniqueKeysWithValues: dockRows.map { ($0.target.shortcutIndex, $0) })
        let assignedCount = min(10, Set(rowsByIndex.keys.filter { (0..<10).contains($0) }).count)
        let statusTitle = Self.statusTitle(isAccessibilityTrusted: isAccessibilityTrusted)

        summaryTitle = [
            statusTitle,
            selectedPreset.menuTitle,
            AppText.DockShortcuts.countTitle(assignedCount)
        ].joined(separator: " | ")
        assignedShortcutCount = assignedCount
        exampleRows = Self.exampleRows(selectedPreset: selectedPreset)
        showDockMappingTitle = AppText.Menu.showDockMapping
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
        updateDockShortcutsTitle = AppText.Menu.updateDockShortcuts
        showLogsTitle = AppText.Menu.showLogs
        checkAccessibilityTitle = isAccessibilityTrusted ? nil : AppText.Menu.checkAccessibility
        openAccessibilitySettingsTitle = isAccessibilityTrusted ? nil : AppText.Menu.openAccessibilitySettings
        quitTitle = AppText.Menu.quit
    }

    private static func statusTitle(isAccessibilityTrusted: Bool) -> String {
        guard isAccessibilityTrusted else {
            return AppText.Status.missingAccessibilityPermission
        }
        return AppText.Status.ready
    }

    private static func exampleRows(selectedPreset: TriggerModifierPreset) -> [ExampleRow] {
        [
            ExampleRow(title: "\(selectedPreset.shortcutLabel(forKeyLabel: "`"))  \(AppText.DockShortcuts.finder)")
        ]
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
}
