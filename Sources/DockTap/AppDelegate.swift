import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logStore = LogStore()
    private let permissionGate = PermissionGate()
    private let settingsStore = SettingsStore()
    private let loginItemController = LoginItemController()
    private let activeAppProvider = ActiveAppProvider()
    private let dockSlotStore = DockSlotStore()
    private lazy var appActivator = AppActivator(logStore: logStore)
    private lazy var windowActor = WindowActor(logStore: logStore)
    private lazy var updateController: UpdateController = {
        let controller = UpdateController(logStore: logStore)
        controller.onAvailabilityChanged = { [weak self] in
            self?.rebuildMenu()
        }
        return controller
    }()

    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var logWindowController: LogWindowController?
    private var eventTapController: EventTapController?
    private var healthReconcileTimer: Timer?
    private var isAccessibilityTrusted = false
    private var selectedTriggerModifierPreset = TriggerModifierPreset.defaultPreset
    private var windowActionsEnabled = false
    private var lastLoginItemFailure: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        selectedTriggerModifierPreset = settingsStore.selectedTriggerModifierPreset
        windowActionsEnabled = settingsStore.windowActionsEnabled
        buildStatusItem()

        logWindowController = LogWindowController(logStore: logStore)
        eventTapController = EventTapController(logStore: logStore) { [weak self] intent in
            self?.handleShortcut(intent)
        }
        eventTapController?.onReadinessChanged = { [weak self] _ in
            self?.rebuildMenu()
        }
        eventTapController?.onReconcileRequested = { [weak self] in
            self?.reconcilePermissionAndTapHealth(prompt: false, reason: "tap recovery")
        }
        eventTapController?.updateTriggerModifierPreset(selectedTriggerModifierPreset)
        eventTapController?.updateWindowActionsEnabled(windowActionsEnabled)

        logStore.append("launch bundle=\(bundleIdentifier) path=\(Bundle.main.bundlePath) trigger=\(selectedTriggerModifierPreset.rawValue)")
        activeAppProvider.start { [weak self] state in
            self?.workspaceStateDidChange(state)
        }

        refreshDock(reason: "launch")
        startHealthReconcileTimer()
        reconcilePermissionAndTapHealth(prompt: true, reason: "launch")
        _ = updateController
    }

    func applicationWillTerminate(_ notification: Notification) {
        healthReconcileTimer?.invalidate()
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

    @objc private func checkForUpdatesFromMenu() {
        updateController.checkForUpdates()
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

    @objc private func toggleWindowActionsEnabled() {
        windowActionsEnabled.toggle()
        settingsStore.windowActionsEnabled = windowActionsEnabled
        eventTapController?.updateWindowActionsEnabled(windowActionsEnabled)
        logStore.append("window snap enabled=\(windowActionsEnabled)")
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
        configureStatusItemButton(item.button)

        statusMenu.delegate = self
        item.menu = statusMenu

        statusItem = item
        rebuildMenu()
    }

    private func configureStatusItemButton(_ button: NSStatusBarButton?) {
        guard let button else {
            return
        }

        guard let image = Bundle.main.image(forResource: "StatusBarIconTemplate") else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "DT"
            return
        }

        image.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
    }

    private func checkPermission(prompt: Bool) {
        reconcilePermissionAndTapHealth(prompt: prompt, reason: prompt ? "manual" : "timer")
    }

    private func startHealthReconcileTimer() {
        guard healthReconcileTimer == nil else {
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkPermission(prompt: false)
        }
        timer.tolerance = 1.0
        healthReconcileTimer = timer
    }

    private func reconcilePermissionAndTapHealth(prompt: Bool, reason: String) {
        let trusted = permissionGate.isTrusted(prompt: prompt)
        let trustChanged = isAccessibilityTrusted != trusted
        isAccessibilityTrusted = trusted
        let tapReady = eventTapController?.isReady == true
        let decision = TapHealthReconciler.evaluate(
            isAccessibilityTrusted: trusted,
            isEventTapReady: tapReady
        )

        guard trusted else {
            if trustChanged || prompt {
                logStore.append("permission missing: grant Accessibility access to the signed DockTap.app bundle=\(bundleIdentifier)")
            }
            if decision.shouldStopTap {
                eventTapController?.stop()
            }
            rebuildMenu()
            return
        }

        if trustChanged || prompt {
            logStore.append("permission trusted: Accessibility access granted")
        }

        guard decision.shouldInstallTap else {
            if trustChanged || prompt {
                rebuildMenu()
            }
            return
        }

        if decision.shouldUpdateSlotSnapshot {
            eventTapController?.updateSlotSnapshot(dockSlotStore.snapshot())
        }

        let didInstall = eventTapController?.install() == true
        let postInstallDecision = TapHealthReconciler.evaluate(
            isAccessibilityTrusted: trusted,
            isEventTapReady: eventTapController?.isReady == true,
            installAttempt: didInstall ? .succeeded : .failed
        )
        if postInstallDecision.shouldRetryInstall {
            logStore.append("tap install not ready after \(reason); will retry during health reconcile")
        }
        rebuildMenu()
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
        switch intent {
        case .windowAction:
            windowActor.perform(intent)
        case .dockSlot, .finder:
            appActivator.perform(intent)
        }
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()

        let loginStatus = loginItemController.status()
        let loginMenuModel = LoginItemMenuModel(status: loginStatus, failureMessage: lastLoginItemFailure)
        let menuModel = MenuContentModel(
            dockRows: dockSlotStore.menuRows(),
            selectedPreset: selectedTriggerModifierPreset,
            isAccessibilityTrusted: isAccessibilityTrusted,
            isEventTapReady: eventTapController?.isReady == true,
            windowActionsEnabled: windowActionsEnabled,
            appName: appName,
            appVersion: appVersion,
            availableUpdateVersion: updateController.availableUpdateVersion
        )

        statusMenu.addItem(disabledItem(menuModel.summaryTitle))
        statusMenu.addItem(.separator())

        statusMenu.addItem(mappingMenuItem(menuModel))
        statusMenu.addItem(triggerModifierMenuItem(menuModel))
        statusMenu.addItem(.separator())

        let windowSnapItem = commandItem(
            title: menuModel.windowSnapToggleTitle,
            action: #selector(toggleWindowActionsEnabled),
            keyEquivalent: ""
        )
        windowSnapItem.state = menuModel.windowSnapToggleIsOn ? .on : .off
        statusMenu.addItem(windowSnapItem)
        statusMenu.addItem(windowSnapMenuItem(menuModel))
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
        if let updateAvailableTitle = menuModel.updateAvailableTitle {
            statusMenu.addItem(commandItem(title: updateAvailableTitle, action: #selector(checkForUpdatesFromMenu), keyEquivalent: ""))
        }
        statusMenu.addItem(commandItem(title: menuModel.checkForUpdatesTitle, action: #selector(checkForUpdatesFromMenu), keyEquivalent: ""))
        statusMenu.addItem(disabledItem(menuModel.versionTitle))
        statusMenu.addItem(.separator())
        statusMenu.addItem(commandItem(title: menuModel.quitTitle, action: #selector(quit), keyEquivalent: ""))
    }

    private func mappingMenuItem(_ menuModel: MenuContentModel) -> NSMenuItem {
        let item = NSMenuItem(title: menuModel.dockShortcutsTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: menuModel.dockShortcutsTitle)
        submenu.addItem(disabledItem(menuModel.finderShortcutTitle))
        submenu.addItem(.separator())
        for row in menuModel.mappingRows {
            submenu.addItem(disabledItem(row.title))
        }
        item.submenu = submenu
        return item
    }

    private func windowSnapMenuItem(_ menuModel: MenuContentModel) -> NSMenuItem {
        let item = NSMenuItem(title: menuModel.windowSnapSubmenuTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: menuModel.windowSnapSubmenuTitle)
        for row in menuModel.windowSnapRows {
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

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Dock Tap"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
