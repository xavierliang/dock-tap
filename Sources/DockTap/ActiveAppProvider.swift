import AppKit

struct WorkspaceAppState: Equatable {
    static let empty = WorkspaceAppState(
        activeBundleIdentifier: nil,
        activeBundleURL: nil,
        runningBundleIdentifiers: [],
        runningBundleURLs: []
    )

    let activeBundleIdentifier: String?
    let activeBundleURL: URL?
    let runningBundleIdentifiers: Set<String>
    let runningBundleURLs: Set<URL>
}

final class ActiveAppProvider {
    private var cachedState = WorkspaceAppState.empty
    private var observers: [NSObjectProtocol] = []

    func start(onChange: @escaping (WorkspaceAppState) -> Void) {
        refresh(onChange: onChange)

        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        observers = names.map { name in
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh(onChange: onChange)
            }
        }
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
    }

    private func refresh(onChange: (WorkspaceAppState) -> Void) {
        let runningApplications = NSWorkspace.shared.runningApplications
        let state = WorkspaceAppState(
            activeBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            activeBundleURL: NSWorkspace.shared.frontmostApplication?.bundleURL?.standardizedFileURL,
            runningBundleIdentifiers: Set(runningApplications.compactMap(\.bundleIdentifier)),
            runningBundleURLs: Set(runningApplications.compactMap { $0.bundleURL?.standardizedFileURL })
        )
        let changed = cachedState != state
        cachedState = state

        if changed {
            onChange(state)
        }
    }
}
