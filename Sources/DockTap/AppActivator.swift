import AppKit

struct AppActivationContext: Equatable {
    let runningBundleIdentifiers: Set<String>
    let finderIsRunning: Bool
    let finderURL: URL?
}

enum AppActivationRoute: Equatable {
    case missingSlot(DockSlotTarget)
    case activateSlot(DockSlotTarget)
    case launchSlot(DockSlotTarget)
    case activateFinder(shortcutLabel: String)
    case launchFinder(URL, shortcutLabel: String)
    case finderUnavailable(shortcutLabel: String)
    case ignoredNonActivationIntent(shortcutLabel: String)
}

final class AppActivator {
    private static let finderBundleID = "com.apple.finder"

    private let logStore: LogStore

    init(logStore: LogStore) {
        self.logStore = logStore
    }

    func perform(_ intent: ShortcutIntent) {
        runOnMain { [weak self] in
            guard let self else {
                return
            }
            execute(Self.route(for: intent, context: self.currentContext()))
        }
    }

    static func route(for intent: ShortcutIntent, context: AppActivationContext) -> AppActivationRoute {
        switch intent {
        case .dockSlot(let target, shortcutLabel: _):
            if target.isMissing {
                return .missingSlot(target)
            }
            if let bundleID = target.bundleIdentifier, context.runningBundleIdentifiers.contains(bundleID) {
                return .activateSlot(target)
            }
            return .launchSlot(target)
        case .finder(shortcutLabel: let shortcutLabel):
            if context.finderIsRunning {
                return .activateFinder(shortcutLabel: shortcutLabel)
            }
            if let finderURL = context.finderURL {
                return .launchFinder(finderURL, shortcutLabel: shortcutLabel)
            }
            return .finderUnavailable(shortcutLabel: shortcutLabel)
        case .windowAction(_, shortcutLabel: let shortcutLabel):
            return .ignoredNonActivationIntent(shortcutLabel: shortcutLabel)
        case .keepAwake(_, shortcutLabel: let shortcutLabel):
            return .ignoredNonActivationIntent(shortcutLabel: shortcutLabel)
        }
    }

    private func execute(_ route: AppActivationRoute) {
        switch route {
        case .missingSlot(let target):
            logStore.append("action start \(target.logDescription)")
            logStore.append("action failed missing \(target.logDescription) path=\(target.appURL.path)")
        case .activateSlot(let target):
            activateSlot(target)
        case .launchSlot(let target):
            launchSlot(target)
        case .activateFinder(let shortcutLabel):
            activateFinder(shortcutLabel: shortcutLabel)
        case .launchFinder(let finderURL, let shortcutLabel):
            launchFinder(at: finderURL, shortcutLabel: shortcutLabel)
        case .finderUnavailable(let shortcutLabel):
            logStore.append("action start Finder shortcut=\(shortcutLabel)")
            logStore.append("action failed Finder app URL unavailable")
        case .ignoredNonActivationIntent(let shortcutLabel):
            logStore.append("action skipped non-activation intent shortcut=\(shortcutLabel)")
        }
    }

    private func activateSlot(_ target: DockSlotTarget) {
        logStore.append("action start \(target.logDescription)")

        guard let runningApp = runningApplication(bundleIdentifier: target.bundleIdentifier) else {
            logStore.append("action activate failed \(target.logDescription) running app unavailable")
            return
        }

        let activated = runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        logStore.append("action \(activated ? "activated" : "activate failed") \(target.logDescription)")
    }

    private func launchSlot(_ target: DockSlotTarget) {
        logStore.append("action start \(target.logDescription)")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: target.appURL, configuration: configuration) { [weak self] app, error in
            if let error {
                self?.logStore.append("action launch failed \(target.logDescription) error=\(error.localizedDescription)")
            } else {
                let bundleID = app?.bundleIdentifier ?? target.bundleIdentifier ?? "-"
                self?.logStore.append("action launched \(target.logDescription) bundle=\(bundleID)")
            }
        }
    }

    private func activateFinder(shortcutLabel: String) {
        logStore.append("action start Finder shortcut=\(shortcutLabel)")

        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: Self.finderBundleID).first else {
            logStore.append("action activate failed Finder running app unavailable")
            return
        }

        let activated = finder.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        logStore.append("action \(activated ? "activated" : "activate failed") Finder")
    }

    private func launchFinder(at finderURL: URL, shortcutLabel: String) {
        logStore.append("action start Finder shortcut=\(shortcutLabel)")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: finderURL, configuration: configuration) { [weak self] app, error in
            if let error {
                self?.logStore.append("action launch failed Finder error=\(error.localizedDescription)")
            } else {
                self?.logStore.append("action launched Finder bundle=\(app?.bundleIdentifier ?? Self.finderBundleID)")
            }
        }
    }

    private func currentContext() -> AppActivationContext {
        AppActivationContext(
            runningBundleIdentifiers: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
            finderIsRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: Self.finderBundleID).isEmpty,
            finderURL: NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.finderBundleID)
        )
    }

    private func runningApplication(bundleIdentifier: String?) -> NSRunningApplication? {
        guard let bundleIdentifier else {
            return nil
        }

        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
