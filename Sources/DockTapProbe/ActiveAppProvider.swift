import AppKit

final class ActiveAppProvider {
    private var cachedBundleID: String?
    private var observer: NSObjectProtocol?

    func start(onChange: @escaping (String?) -> Void) {
        refresh(onChange: onChange)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh(onChange: onChange)
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func refresh(onChange: (String?) -> Void) {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let changed = cachedBundleID != bundleID
        cachedBundleID = bundleID

        if changed {
            onChange(bundleID)
        }
    }
}
