import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logStore = LogStore()
    private let permissionGate = PermissionGate()
    private let activeAppProvider = ActiveAppProvider()

    private var statusItem: NSStatusItem?
    private var logWindowController: LogWindowController?
    private var eventTapController: EventTapController?
    private var permissionTimer: Timer?
    private var didInstallTap = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()

        logWindowController = LogWindowController(logStore: logStore)
        eventTapController = EventTapController(logStore: logStore)

        logStore.append("launch bundle=\(Bundle.main.bundleIdentifier ?? "-") path=\(Bundle.main.bundlePath)")
        activeAppProvider.start { [weak self] bundleID in
            self?.eventTapController?.updateFrontmostBundleID(bundleID)
            self?.logStore.append("frontmost=\(bundleID ?? "-")")
        }

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

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "DT"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Logs", action: #selector(showLogs), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Check Accessibility", action: #selector(checkPermissionFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }

    private func checkPermission(prompt: Bool) {
        guard permissionGate.isTrusted(prompt: prompt) else {
            logStore.append("permission missing: grant Accessibility access to the packaged DockTapProbe.app")
            schedulePermissionRecheck()
            return
        }

        logStore.append("permission trusted: Accessibility access granted")

        if !didInstallTap {
            guard eventTapController?.install() == true else {
                schedulePermissionRecheck()
                return
            }
            didInstallTap = true
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
}
