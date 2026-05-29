import Foundation

public final class ClosedLidFileJournalStore: ClosedLidJournalStoring {
    public static let defaultJournalURL = URL(
        fileURLWithPath: "/Library/Application Support/DockTap/ClosedLidKeepAwake/journal.json",
        isDirectory: false
    )

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL = ClosedLidFileJournalStore.defaultJournalURL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> ClosedLidJournalEntry? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ClosedLidJournalEntry.self, from: data)
    }

    public func savePendingEnable(_ entry: ClosedLidJournalEntry) throws {
        precondition(entry.phase == .pendingEnable, "savePendingEnable requires a pending journal entry")
        try write(entry)
    }

    public func markActive(_ entry: ClosedLidJournalEntry) throws {
        precondition(entry.phase == .active, "markActive requires an active journal entry")
        try write(entry)
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }

    private func write(_ entry: ClosedLidJournalEntry) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(entry)
        try data.write(to: fileURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
