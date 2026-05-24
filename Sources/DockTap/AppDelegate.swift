import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logStore = LogStore()
    private let permissionGate = PermissionGate()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()

        logWindowController = LogWindowController(logStore: logStore)
        eventTapController = EventTapController(logStore: logStore) { [weak self] intent in
            self?.handleShortcut(intent)
        }

        logStore.append("launch bundle=\(Bundle.main.bundleIdentifier ?? "-") path=\(Bundle.main.bundlePath)")
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

    @objc private func refreshDockFromMenu() {
        refreshDock(reason: "manual")
    }

    func menuWillOpen(_ menu: NSMenu) {
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
                logStore.append("permission missing: grant Accessibility access to the packaged DockTap.app")
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

        let summary = dockSlotStore.summary()
        statusMenu.addItem(disabledItem(
            "Accessibility: \(isAccessibilityTrusted ? "trusted" : "missing") | Tap: \(didInstallTap ? "ready" : "not ready") | Dock slots: \(summary.slotCount)"
        ))
        statusMenu.addItem(.separator())

        let rowsByIndex = Dictionary(uniqueKeysWithValues: dockSlotStore.menuRows().map { ($0.target.shortcutIndex, $0) })
        for shortcutIndex in 0..<10 {
            if let row = rowsByIndex[shortcutIndex] {
                statusMenu.addItem(disabledItem(slotTitle(row: row)))
            } else {
                let label = DockSlotStore.shortcutLabel(for: shortcutIndex)
                statusMenu.addItem(disabledItem("\(label)  shortcutIndex=\(shortcutIndex) unassigned"))
            }
        }

        statusMenu.addItem(.separator())
        statusMenu.addItem(disabledItem("leftOption+`  Finder"))
        statusMenu.addItem(.separator())
        statusMenu.addItem(commandItem(title: "Refresh Dock", action: #selector(refreshDockFromMenu), keyEquivalent: "r"))
        statusMenu.addItem(commandItem(title: "Show Logs", action: #selector(showLogs), keyEquivalent: "l"))
        statusMenu.addItem(commandItem(title: "Check Accessibility", action: #selector(checkPermissionFromMenu), keyEquivalent: ""))
        statusMenu.addItem(.separator())
        statusMenu.addItem(commandItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
    }

    private func slotTitle(row: DockSlotMenuRow) -> String {
        let target = row.target
        return "\(target.shortcutLabel)  shortcutIndex=\(target.shortcutIndex) dockOrdinal=\(target.dockOrdinal) \(target.displayName) [\(row.status.rawValue)]"
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
}
