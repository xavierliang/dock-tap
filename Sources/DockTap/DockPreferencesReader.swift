import Foundation

struct DockAppEntry: Equatable {
    let dockOrdinal: Int
    let appURL: URL
    let displayName: String
    let bundleIdentifier: String?
    let isMissing: Bool
}

struct DockPreferencesParseResult: Equatable {
    let apps: [DockAppEntry]
    let skippedCount: Int
}

struct DockPreferencesReader {
    private let preferencesAppID: CFString
    private let copyPreferenceValue: (CFString, CFString) -> Any?
    private let synchronizePreferences: (CFString) -> Bool
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        preferencesAppID: CFString = "com.apple.dock" as CFString,
        copyPreferenceValue: @escaping (CFString, CFString) -> Any? = { key, appID in
            CFPreferencesCopyAppValue(key, appID)
        },
        synchronizePreferences: @escaping (CFString) -> Bool = { appID in
            CFPreferencesAppSynchronize(appID)
        }
    ) {
        self.fileManager = fileManager
        self.preferencesAppID = preferencesAppID
        self.copyPreferenceValue = copyPreferenceValue
        self.synchronizePreferences = synchronizePreferences
    }

    func readCurrentDockApps(limit: Int = 10) -> DockPreferencesParseResult {
        _ = synchronizePreferences(preferencesAppID)
        guard let persistentApps = copyPreferenceValue(
            "persistent-apps" as CFString,
            preferencesAppID
        ) else {
            return DockPreferencesParseResult(apps: [], skippedCount: 0)
        }

        return parsePersistentApps(persistentApps, limit: limit)
    }

    func parsePersistentApps(_ value: Any, limit: Int = 10) -> DockPreferencesParseResult {
        guard let tiles = persistentAppsArray(from: value) else {
            return DockPreferencesParseResult(apps: [], skippedCount: 0)
        }

        var apps: [DockAppEntry] = []
        var skippedCount = 0

        for (offset, rawTile) in tiles.enumerated() {
            let dockOrdinal = offset + 1
            guard let entry = parseAppEntry(rawTile, dockOrdinal: dockOrdinal) else {
                skippedCount += 1
                continue
            }

            if apps.count < limit {
                apps.append(entry)
            }
        }

        return DockPreferencesParseResult(apps: apps, skippedCount: skippedCount)
    }

    private func parseAppEntry(_ value: Any, dockOrdinal: Int) -> DockAppEntry? {
        guard
            let tile = dictionary(value),
            let tileData = dictionary(tile["tile-data"]),
            let fileData = dictionary(tileData["file-data"]),
            let appURL = appFileURL(from: fileData)
        else {
            return nil
        }

        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory)
        let isMissing = !(exists && isDirectory.boolValue)
        let label = tileData["file-label"] as? String
        let displayName = readableName(label: label, appURL: appURL)
        let plistBundleID = tileData["bundle-identifier"] as? String
        let bundleID = Bundle(url: appURL)?.bundleIdentifier ?? plistBundleID

        return DockAppEntry(
            dockOrdinal: dockOrdinal,
            appURL: appURL,
            displayName: displayName,
            bundleIdentifier: bundleID,
            isMissing: isMissing
        )
    }

    private func persistentAppsArray(from value: Any) -> [Any]? {
        if let array = value as? [Any] {
            return array
        }

        return dictionary(value)?["persistent-apps"] as? [Any]
    }

    private func dictionary(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }

        guard let nsDictionary = value as? NSDictionary else {
            return nil
        }

        var result: [String: Any] = [:]
        for (key, value) in nsDictionary {
            guard let key = key as? String else {
                continue
            }
            result[key] = value
        }
        return result
    }

    private func appFileURL(from fileData: [String: Any]) -> URL? {
        guard let rawURL = fileData["_CFURLString"] as? String else {
            return nil
        }

        let url: URL?
        if rawURL.hasPrefix("file:") {
            url = URL(string: rawURL)?.standardizedFileURL
        } else if rawURL.hasPrefix("/") || rawURL.hasPrefix("~") {
            let path = (rawURL as NSString).expandingTildeInPath
            url = URL(fileURLWithPath: path).standardizedFileURL
        } else {
            url = nil
        }

        guard let url, url.isFileURL, url.pathExtension.lowercased() == "app" else {
            return nil
        }
        return url
    }

    private func readableName(label: String?, appURL: URL) -> String {
        if let label, !label.isEmpty {
            return label
        }

        return appURL.deletingPathExtension().lastPathComponent
    }
}
