import Foundation

enum DockSlotStatus: String, Equatable {
    case active
    case running
    case notRunning = "not running"
    case missing
}

struct DockSlotMenuRow: Equatable {
    let target: DockSlotTarget
    let status: DockSlotStatus
}

final class DockSlotStore {
    private let reader: DockPreferencesReader
    private let lock = NSLock()

    private var targets: [DockSlotTarget] = []
    private var workspaceState = WorkspaceAppState.empty

    init(reader: DockPreferencesReader = DockPreferencesReader()) {
        self.reader = reader
    }

    @discardableResult
    func refreshFromDockPreferences() -> DockPreferencesParseResult {
        let result = reader.readCurrentDockApps()
        replace(entries: result.apps)
        return result
    }

    func replace(entries: [DockAppEntry]) {
        let newTargets = entries.prefix(10).enumerated().map { shortcutIndex, entry in
            Self.makeTarget(entry: entry, shortcutIndex: shortcutIndex)
        }

        lock.lock()
        targets = newTargets
        lock.unlock()
    }

    func updateWorkspaceState(_ state: WorkspaceAppState) {
        lock.lock()
        workspaceState = state
        lock.unlock()
    }

    func snapshot() -> DockSlotSnapshot {
        lock.lock()
        let currentTargets = targets
        lock.unlock()
        return DockSlotSnapshot(targets: currentTargets)
    }

    func menuRows() -> [DockSlotMenuRow] {
        lock.lock()
        let currentTargets = targets
        let state = workspaceState
        lock.unlock()

        return currentTargets.map { target in
            DockSlotMenuRow(target: target, status: status(for: target, state: state))
        }
    }

    private static func makeTarget(entry: DockAppEntry, shortcutIndex: Int) -> DockSlotTarget {
        DockSlotTarget(
            id: "slot-\(shortcutIndex)-dock-\(entry.dockOrdinal)-\(entry.appURL.path)",
            shortcutIndex: shortcutIndex,
            dockOrdinal: entry.dockOrdinal,
            appURL: entry.appURL,
            displayName: entry.displayName,
            bundleIdentifier: entry.bundleIdentifier,
            isMissing: entry.isMissing
        )
    }

    private func status(for target: DockSlotTarget, state: WorkspaceAppState) -> DockSlotStatus {
        guard !target.isMissing else {
            return .missing
        }

        if let bundleID = target.bundleIdentifier {
            if state.activeBundleIdentifier == bundleID {
                return .active
            }
            if state.runningBundleIdentifiers.contains(bundleID) {
                return .running
            }
        }

        if state.activeBundleURL == target.appURL {
            return .active
        }
        if state.runningBundleURLs.contains(target.appURL) {
            return .running
        }

        return .notRunning
    }
}
