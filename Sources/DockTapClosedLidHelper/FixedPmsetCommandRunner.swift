import DockTapClosedLidHelperCore
import Foundation

public final class FixedPmsetCommandRunner: ClosedLidPowerCommandRunning {
    private let executableURL = URL(fileURLWithPath: "/usr/bin/pmset", isDirectory: false)

    public init() {}

    public func run(_ command: ClosedLidPowerCommand) -> ClosedLidPowerCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = command.pmsetArguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ClosedLidPowerCommandResult(
                terminationStatus: 127,
                standardError: error.localizedDescription
            )
        }

        return ClosedLidPowerCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            standardError: String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}
