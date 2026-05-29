import Foundation
import os

public final class LaunchDaemonLogger {
    private let logger = Logger(subsystem: "ai.resopod.docktap", category: "ClosedLidHelper")

    public init() {}

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        writeToStandardError("info", message)
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        writeToStandardError("error", message)
    }

    private func writeToStandardError(_ level: String, _ message: String) {
        let line = "[closed-lid-helper] \(level): \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
