import XCTest
@testable import DockTap

final class DockPreferencesReaderTests: XCTestCase {
    private let reader = DockPreferencesReader()
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs = []
        try super.tearDownWithError()
    }

    func testReadSynchronizesDockPreferencesBeforeCopyingPersistentApps() {
        var calls: [String] = []
        let reader = DockPreferencesReader(
            copyPreferenceValue: { key, appID in
                calls.append("copy:\(key as String):\(appID as String)")
                return ["persistent-apps": []]
            },
            synchronizePreferences: { appID in
                calls.append("sync:\(appID as String)")
                return true
            }
        )

        let result = reader.readCurrentDockApps()

        XCTAssertEqual(result, DockPreferencesParseResult(apps: [], skippedCount: 0))
        XCTAssertEqual(calls, ["sync:com.apple.dock", "copy:persistent-apps:com.apple.dock"])
    }

    func testParsesAppsInDockOrderAndSkipsNonAppTiles() throws {
        let firstApp = try makeTemporaryApp(named: "First.app")
        let secondApp = try makeTemporaryApp(named: "Second.app")
        let missingApp = URL(fileURLWithPath: "/Applications/MissingDockTapTest.app")
        let plist: [String: Any] = [
            "persistent-apps": [
                appTile(path: firstApp.path, label: "First", bundleIdentifier: "dev.local.First"),
                documentTile(path: "/Users/example/Documents/readme.txt", label: "Readme"),
                ["tile-type": "spacer-tile", "tile-data": ["file-label": "Spacer"]],
                appTile(urlString: secondApp.absoluteString, label: "Second", bundleIdentifier: "dev.local.Second"),
                appTile(path: missingApp.path, label: "Missing", bundleIdentifier: "dev.local.Missing")
            ]
        ]

        let result = reader.parsePersistentApps(plist)

        XCTAssertEqual(result.apps.map(\.displayName), ["First", "Second", "Missing"])
        XCTAssertEqual(result.apps.map(\.dockOrdinal), [1, 4, 5])
        XCTAssertEqual(result.skippedCount, 2)
        XCTAssertEqual(result.apps.map(\.isMissing), [false, false, true])
        XCTAssertEqual(result.apps.last?.bundleIdentifier, "dev.local.Missing")
    }

    func testKeepsOnlyFirstTenAcceptedAppsAndCountsLaterSkippedTiles() {
        var tiles = (1...12).map { index in
            appTile(path: "/Applications/Mock\(index).app", label: "Mock\(index)")
        }
        tiles.append(documentTile(path: "/Users/example/Documents/readme.txt", label: "Readme"))
        tiles.append(["tile-type": "file-tile", "tile-data": ["file-label": "Malformed"]])

        let result = reader.parsePersistentApps(["persistent-apps": tiles])

        XCTAssertEqual(result.apps.count, 10)
        XCTAssertEqual(result.apps.first?.displayName, "Mock1")
        XCTAssertEqual(result.apps.last?.displayName, "Mock10")
        XCTAssertEqual(result.apps.last?.dockOrdinal, 10)
        XCTAssertEqual(result.skippedCount, 2)
    }

    func testFallsBackToAppPathNameWhenFileLabelIsMissing() {
        let result = reader.parsePersistentApps([
            appTile(path: "/Applications/Name From Path.app", label: nil)
        ])

        XCTAssertEqual(result.apps.first?.displayName, "Name From Path")
    }

    func testParsesSanitizedRealDockFixture() throws {
        let fixture = try loadFixture(named: "real-dock-persistent-apps-sanitized.plist")
        let result = reader.parsePersistentApps(fixture)

        XCTAssertEqual(result.apps.map(\.displayName), ["Safari", "Mail", "Notes", "MissingSanitized"])
        XCTAssertEqual(result.apps.map(\.dockOrdinal), [1, 2, 4, 5])
        XCTAssertEqual(result.skippedCount, 2)
        XCTAssertEqual(result.apps[0].bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(result.apps[1].bundleIdentifier, "com.apple.mail")
        XCTAssertTrue(result.apps[3].isMissing)
    }

    private func makeTemporaryApp(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockTapTests-\(UUID().uuidString)", isDirectory: true)
        let appURL = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        temporaryURLs.append(directory)
        return appURL
    }

    private func loadFixture(named name: String) throws -> Any {
        let currentFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = currentFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        let data = try Data(contentsOf: fixtureURL)
        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }
}

final class DockPreferencesReaderSmokeTests: XCTestCase {
    func testReadsCurrentUsersDockPreferencesWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["DOCK_TAP_SMOKE_REAL_DOCK"] == "1" else {
            throw XCTSkip("set DOCK_TAP_SMOKE_REAL_DOCK=1 to read this user's Dock preferences")
        }

        let result = DockPreferencesReader().readCurrentDockApps()
        print("Dock Tap real Dock smoke: apps=\(result.apps.count) skipped=\(result.skippedCount)")
        for app in result.apps {
            print("shortcut? dockOrdinal=\(app.dockOrdinal) name=\(app.displayName) path=\(app.appURL.path)")
        }
        XCTAssertGreaterThanOrEqual(result.apps.count, 0)
    }
}

private func appTile(
    path: String? = nil,
    urlString: String? = nil,
    label: String?,
    bundleIdentifier: String? = nil
) -> [String: Any] {
    var tileData: [String: Any] = [
        "file-data": [
            "_CFURLString": urlString ?? path ?? "",
            "_CFURLStringType": urlString == nil ? 0 : 15
        ],
        "file-type": 41
    ]

    if let label {
        tileData["file-label"] = label
    }
    if let bundleIdentifier {
        tileData["bundle-identifier"] = bundleIdentifier
    }

    return [
        "tile-type": "file-tile",
        "tile-data": tileData
    ]
}

private func documentTile(path: String, label: String) -> [String: Any] {
    [
        "tile-type": "file-tile",
        "tile-data": [
            "file-label": label,
            "file-data": [
                "_CFURLString": path,
                "_CFURLStringType": 0
            ],
            "file-type": 1
        ]
    ]
}
