import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logStore = LogStore()
    private let permissionGate = PermissionGate()
    private let settingsStore = SettingsStore()
    private let loginItemController = LoginItemController()
    private let activeAppProvider = ActiveAppProvider()
    private let dockSlotStore = DockSlotStore()
    private lazy var appActivator = AppActivator(logStore: logStore)

    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var logWindowController: LogWindowController?
    private var eventTapController: EventTapController?
    private var permissionTimer: Timer?
    private var didInstallTap = false
    private var isAccessibilityTrusted = false
    private var selectedTriggerModifierPreset = TriggerModifierPreset.defaultPreset
    private var lastLoginItemFailure: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        selectedTriggerModifierPreset = settingsStore.selectedTriggerModifierPreset
        buildStatusItem()

        logWindowController = LogWindowController(logStore: logStore)
        eventTapController = EventTapController(logStore: logStore) { [weak self] intent in
            self?.handleShortcut(intent)
        }
        eventTapController?.updateTriggerModifierPreset(selectedTriggerModifierPreset)

        logStore.append("launch bundle=\(bundleIdentifier) path=\(Bundle.main.bundlePath) trigger=\(selectedTriggerModifierPreset.rawValue)")
        activeAppProvider.start { [weak self] state in
            self?.workspaceStateDidChange(state)
        }

        refreshDock(reason: "launch")
        checkPermission(prompt: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        activeAppProvider.stop()
        eventTapController?.stop()
    }

    @objc private func showLogs() {
        logWindowController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func checkPermissionFromMenu() {
        checkPermission(prompt: true)
    }

    @objc private func openAccessibilitySettingsFromMenu() {
        permissionGate.openAccessibilitySettings()
    }

    @objc private func refreshDockFromMenu() {
        refreshDock(reason: "manual")
    }

    @objc private func selectTriggerModifierPreset(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let preset = TriggerModifierPreset(rawValue: rawValue)
        else {
            return
        }

        selectedTriggerModifierPreset = preset
        settingsStore.selectedTriggerModifierPreset = preset
        eventTapController?.updateTriggerModifierPreset(preset)
        logStore.append("trigger modifier preset=\(preset.rawValue)")
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        let currentStatus = loginItemController.status()
        let result = currentStatus.isEnabled ? loginItemController.disable() : loginItemController.enable()

        if let failure = result.failureMessage {
            lastLoginItemFailure = failure
            logStore.append("login item \(failure); status=\(result.status.displayValue)")
        } else {
            lastLoginItemFailure = nil
            logStore.append("login item status=\(result.status.displayValue) appPath=\(Bundle.main.bundlePath)")
        }

        if result.status == .requiresApproval {
            logStore.append("login item requires approval in System Settings > General > Login Items")
        }

        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else {
            return
        }
        refreshDock(reason: "menu")
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "DT"

        statusMenu.delegate = self
        item.menu = statusMenu

        statusItem = item
        rebuildMenu()
    }

    private func checkPermission(prompt: Bool) {
        let trusted = permissionGate.isTrusted(prompt: prompt)
        let changed = isAccessibilityTrusted != trusted
        isAccessibilityTrusted = trusted

        guard trusted else {
            if changed || prompt {
                logStore.append("permission missing: grant Accessibility access to the signed DockTap.app bundle=\(bundleIdentifier)")
            }
            rebuildMenu()
            schedulePermissionRecheck()
            return
        }

        if changed || prompt {
            logStore.append("permission trusted: Accessibility access granted")
        }

        if !didInstallTap {
            eventTapController?.updateSlotSnapshot(dockSlotStore.snapshot())
            guard eventTapController?.install() == true else {
                rebuildMenu()
                schedulePermissionRecheck()
                return
            }
            didInstallTap = true
            rebuildMenu()
        }

        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func schedulePermissionRecheck() {
        guard permissionTimer == nil else {
            return
        }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPermission(prompt: false)
        }
    }

    private func refreshDock(reason: String) {
        let result = dockSlotStore.refreshFromDockPreferences()
        eventTapController?.updateSlotSnapshot(dockSlotStore.snapshot())
        logStore.append("dock refresh reason=\(reason) slots=\(result.apps.count) skipped=\(result.skippedCount)")
        rebuildMenu()
    }

    private func workspaceStateDidChange(_ state: WorkspaceAppState) {
        dockSlotStore.updateWorkspaceState(state)
        logStore.append("workspace active=\(state.activeBundleIdentifier ?? "-") running=\(state.runningBundleIdentifiers.count)")
        rebuildMenu()
    }

    private func handleShortcut(_ intent: ShortcutIntent) {
        appActivator.perform(intent)
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()

        let loginStatus = loginItemController.status()
        let loginMenuModel = LoginItemMenuModel(status: loginStatus, failureMessage: lastLoginItemFailure)
        let menuModel = MenuContentModel(
            dockRows: dockSlotStore.menuRows(),
            selectedPreset: selectedTriggerModifierPreset,
            isAccessibilityTrusted: isAccessibilityTrusted,
            isEventTapReady: didInstallTap
        )

        statusMenu.addItem(disabledItem(menuModel.summaryTitle))
        statusMenu.addItem(.separator())

        for row in menuModel.exampleRows {
            statusMenu.addItem(disabledItem(row.title))
        }

        statusMenu.addItem(.separator())
        statusMenu.addItem(mappingMenuItem(menuModel))
        statusMenu.addItem(triggerModifierMenuItem(menuModel))
        statusMenu.addItem(.separator())

        let loginItem = commandItem(title: loginMenuModel.title, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = loginMenuModel.isChecked ? .on : .off
        statusMenu.addItem(loginItem)
        for hint in loginMenuModel.hintRows {
            statusMenu.addItem(disabledItem(hint))
        }
        if let title = menuModel.checkAccessibilityTitle {
            statusMenu.addItem(commandItem(title: title, action: #selector(checkPermissionFromMenu), keyEquivalent: ""))
        }
        if let title = menuModel.openAccessibilitySettingsTitle {
            statusMenu.addItem(commandItem(title: title, action: #selector(openAccessibilitySettingsFromMenu), keyEquivalent: ""))
        }

        statusMenu.addItem(commandItem(title: menuModel.updateDockShortcutsTitle, action: #selector(refreshDockFromMenu), keyEquivalent: ""))
        statusMenu.addItem(commandItem(title: menuModel.showLogsTitle, action: #selector(showLogs), keyEquivalent: ""))
        statusMenu.addItem(.separator())
        statusMenu.addItem(commandItem(title: menuModel.quitTitle, action: #selector(quit), keyEquivalent: ""))
    }

    private func mappingMenuItem(_ menuModel: MenuContentModel) -> NSMenuItem {
        let item = NSMenuItem(title: menuModel.showDockMappingTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: menuModel.showDockMappingTitle)
        for row in menuModel.mappingRows {
            submenu.addItem(disabledItem(row.title))
        }
        item.submenu = submenu
        return item
    }

    private func triggerModifierMenuItem(_ menuModel: MenuContentModel) -> NSMenuItem {
        let item = NSMenuItem(title: menuModel.triggerModifierTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: AppText.Menu.triggerModifier)
        for row in menuModel.triggerRows {
            let presetItem = commandItem(title: row.title, action: #selector(selectTriggerModifierPreset), keyEquivalent: "")
            presetItem.representedObject = row.preset.rawValue
            presetItem.state = row.isSelected ? .on : .off
            submenu.addItem(presetItem)
        }
        item.submenu = submenu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func commandItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "ai.resopod.docktap"
    }
}
