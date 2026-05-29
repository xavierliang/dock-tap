import CoreGraphics
import Foundation
import IOKit

protocol ClosedLidDisplaySleepControlling: AnyObject {
    func setKeepAwakeActive(_ isActive: Bool)
    func invalidate()
}

protocol ClosedLidClamshellStateProviding {
    func isLidClosed() -> Bool?
}

protocol ClosedLidDisplayTopologyProviding {
    func hasActiveExternalDisplay() -> Bool
}

struct ClosedLidDisplaySleepCommandResult: Equatable {
    let terminationStatus: Int32
    let standardError: String

    var succeeded: Bool {
        terminationStatus == 0
    }
}

protocol ClosedLidDisplaySleepCommandRunning {
    func sleepDisplays() -> ClosedLidDisplaySleepCommandResult
}

final class ClosedLidDisplaySleepController: ClosedLidDisplaySleepControlling {
    private let clamshellStateProvider: ClosedLidClamshellStateProviding
    private let displayTopologyProvider: ClosedLidDisplayTopologyProviding
    private let commandRunner: ClosedLidDisplaySleepCommandRunning
    private let logStore: LogStore
    private let monitorInterval: TimeInterval

    private var monitorTimer: Timer?
    private var isKeepAwakeActive = false
    private var lastObservedLidClosed: Bool?
    private var didLogUnavailableClamshellState = false

    init(
        clamshellStateProvider: ClosedLidClamshellStateProviding = IOKitClamshellStateProvider(),
        displayTopologyProvider: ClosedLidDisplayTopologyProviding = CoreGraphicsDisplayTopologyProvider(),
        commandRunner: ClosedLidDisplaySleepCommandRunning = PmsetDisplaySleepCommandRunner(),
        logStore: LogStore,
        monitorInterval: TimeInterval = 2
    ) {
        self.clamshellStateProvider = clamshellStateProvider
        self.displayTopologyProvider = displayTopologyProvider
        self.commandRunner = commandRunner
        self.logStore = logStore
        self.monitorInterval = monitorInterval
    }

    func setKeepAwakeActive(_ isActive: Bool) {
        guard isKeepAwakeActive != isActive else {
            return
        }

        isKeepAwakeActive = isActive
        lastObservedLidClosed = nil
        didLogUnavailableClamshellState = false

        if isActive {
            startMonitoring()
            evaluateNow()
        } else {
            stopMonitoring()
        }
    }

    func invalidate() {
        stopMonitoring()
        isKeepAwakeActive = false
        lastObservedLidClosed = nil
        didLogUnavailableClamshellState = false
    }

    func evaluateNow() {
        guard isKeepAwakeActive else {
            return
        }

        guard let isLidClosed = clamshellStateProvider.isLidClosed() else {
            if !didLogUnavailableClamshellState {
                logStore.append("closed-lid display sleep skipped: clamshell state unavailable")
                didLogUnavailableClamshellState = true
            }
            return
        }

        didLogUnavailableClamshellState = false
        guard isLidClosed else {
            lastObservedLidClosed = false
            return
        }

        guard lastObservedLidClosed != true else {
            return
        }
        lastObservedLidClosed = true

        guard !displayTopologyProvider.hasActiveExternalDisplay() else {
            logStore.append("closed-lid display sleep skipped: external display active")
            return
        }

        let result = commandRunner.sleepDisplays()
        if result.succeeded {
            logStore.append("closed-lid display sleep requested")
        } else {
            logStore.append("closed-lid display sleep failed: \(result.failureMessage)")
        }
    }

    private func startMonitoring() {
        guard monitorTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: monitorInterval, repeats: true) { [weak self] _ in
            self?.evaluateNow()
        }
        timer.tolerance = min(0.5, monitorInterval / 4)
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    private func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }
}

struct IOKitClamshellStateProvider: ClosedLidClamshellStateProviding {
    func isLidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            return nil
        }
        defer {
            IOObjectRelease(service)
        }

        let property = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        return (property as? NSNumber)?.boolValue
    }
}

struct CoreGraphicsDisplayTopologyProvider: ClosedLidDisplayTopologyProviding {
    func hasActiveExternalDisplay() -> Bool {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return false
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return false
        }

        return displays.prefix(Int(displayCount)).contains { display in
            CGDisplayIsBuiltin(display) == 0
        }
    }
}

struct PmsetDisplaySleepCommandRunner: ClosedLidDisplaySleepCommandRunning {
    private let executableURL = URL(fileURLWithPath: "/usr/bin/pmset", isDirectory: false)

    func sleepDisplays() -> ClosedLidDisplaySleepCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["displaysleepnow"]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ClosedLidDisplaySleepCommandResult(
                terminationStatus: 127,
                standardError: error.localizedDescription
            )
        }

        return ClosedLidDisplaySleepCommandResult(
            terminationStatus: process.terminationStatus,
            standardError: String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private extension ClosedLidDisplaySleepCommandResult {
    var failureMessage: String {
        let trimmedError = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedError.isEmpty else {
            return "pmset displaysleepnow exited \(terminationStatus)"
        }
        return trimmedError
    }
}
