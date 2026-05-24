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
    private var lastSkippedCount = 0

    init(reader: DockPreferencesReader = DockPreferencesReader()) {
        self.reader = reader
    }

    @discardableResult
    func refreshFromDockPreferences() -> DockPreferencesParseResult {
        let result = reader.readCurrentDockApps()
        replace(entries: result.apps, skippedCount: result.skippedCount)
        return result
    }

    func replace(entries: [DockAppEntry], skippedCount: Int = 0) {
        let newTargets = entries.prefix(10).enumerated().map { shortcutIndex, entry in
            Self.makeTarget(entry: entry, shortcutIndex: shortcutIndex)
        }

        lock.lock()
        targets = newTargets
        lastSkippedCount = skippedCount
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

    func summary() -> (slotCount: Int, skippedCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (targets.count, lastSkippedCount)
    }

    static func shortcutLabel(for shortcutIndex: Int) -> String {
        switch shortcutIndex {
        case 0...8:
            "leftOption+\(shortcutIndex + 1)"
        case 9:
            "leftOption+0"
        default:
            "leftOption+?"
        }
    }

    private static func makeTarget(entry: DockAppEntry, shortcutIndex: Int) -> DockSlotTarget {
        DockSlotTarget(
            id: "slot-\(shortcutIndex)-dock-\(entry.dockOrdinal)-\(entry.appURL.path)",
            shortcutLabel: shortcutLabel(for: shortcutIndex),
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
