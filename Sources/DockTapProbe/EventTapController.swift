import CoreGraphics
import Foundation

final class EventTapController {
    private let logStore: LogStore
    private let decider = KeyEventDecider()
    private let frontmostLock = NSLock()
    private let tapLock = NSLock()

    private var cachedFrontmostBundleID: String?
    private var modifierState = ModifierState()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?

    init(logStore: LogStore) {
        self.logStore = logStore
    }

    func updateFrontmostBundleID(_ bundleID: String?) {
        frontmostLock.lock()
        cachedFrontmostBundleID = bundleID
        frontmostLock.unlock()
    }

    func install() -> Bool {
        guard !isTapRunningOrInstalling() else {
            logStore.append("tap already installed")
            return true
        }

        let installResult = TapInstallResult()
        let thread = Thread { [weak self] in
            guard let self else {
                installResult.finish(success: false, message: "tap failed: controller was released before install")
                return
            }
            self.runTapThread(installResult: installResult)
        }
        thread.name = "DockTapProbe Event Tap"

        tapLock.lock()
        tapThread = thread
        tapLock.unlock()
        thread.start()

        let result = installResult.wait(timeout: 2.0)
        logStore.append(result.message)
        if !result.success {
            clearTapState()
        }
        return result.success
    }

    func stop() {
        let state = currentTapState()
        guard let tap = state.tap else {
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoop = state.runLoop, let source = state.source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
        CFMachPortInvalidate(tap)
        clearTapState()
        logStore.append("tap stopped")
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<EventTapController>
            .fromOpaque(refcon)
            .takeUnretainedValue()

        return controller.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            scheduleTapRecovery(type: type)
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let currentFrontmostBundleID = currentFrontmostSnapshot()

        switch type {
        case .flagsChanged:
            let isDown = Self.isKeyDown(keyCode)
            modifierState.setPhysicalKey(keyCode, isDown: isDown)
            enqueueRecord(
                type: "flagsChanged",
                keyCode: keyCode,
                frontmostBundleID: currentFrontmostBundleID,
                match: nil,
                result: .stateOnly
            )
            return Unmanaged.passUnretained(event)

        case .keyDown, .keyUp:
            modifierState.resync(readKeyDown: Self.isKeyDown)
            let decision = decider.decide(
                kind: type == .keyDown ? .keyDown : .keyUp,
                keyCode: keyCode,
                modifiers: modifierState.snapshot,
                frontmostBundleID: currentFrontmostBundleID
            )
            enqueueRecord(
                type: Self.name(for: type),
                keyCode: keyCode,
                frontmostBundleID: currentFrontmostBundleID,
                match: decision.match,
                result: decision.result
            )
            return decision.consumesEvent ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func enqueueRecord(
        type: String,
        keyCode: UInt16?,
        frontmostBundleID: String?,
        match: RuleMatch?,
        result: ProbeEventResult
    ) {
        let record = ProbeEventRecord(
            timestamp: Date.timeIntervalSinceReferenceDate,
            eventType: type,
            keyCode: keyCode,
            modifiers: modifierState.snapshot,
            frontmostBundleID: frontmostBundleID,
            matchedRuleID: match?.id,
            result: result
        )

        DispatchQueue.main.async { [logStore] in
            logStore.append(record)
        }
    }

    private func currentFrontmostSnapshot() -> String? {
        frontmostLock.lock()
        defer { frontmostLock.unlock() }
        return cachedFrontmostBundleID
    }

    private func runTapThread(installResult: TapInstallResult) {
        let mask = Self.eventMask(.keyDown, .keyUp, .flagsChanged)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            installResult.finish(
                success: false,
                message: "tap failed: CGEvent.tapCreate returned nil; check Accessibility trust and Secure Input"
            )
            return
        }
        guard !installResult.isAbandoned else {
            CFMachPortInvalidate(tap)
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            installResult.finish(success: false, message: "tap failed: could not create run loop source")
            return
        }
        guard !installResult.isAbandoned else {
            CFMachPortInvalidate(tap)
            return
        }

        guard let runLoop = CFRunLoopGetCurrent() else {
            CFMachPortInvalidate(tap)
            installResult.finish(success: false, message: "tap failed: could not get current run loop")
            return
        }
        guard !installResult.isAbandoned else {
            CFMachPortInvalidate(tap)
            return
        }

        guard storeTapIfActive(tap: tap, source: source, runLoop: runLoop, installResult: installResult) else {
            CFMachPortInvalidate(tap)
            return
        }

        guard installResult.finish(
            success: true,
            message: "tap installed: active session keyboard tap enabled on dedicated run loop"
        ) else {
            CFMachPortInvalidate(tap)
            clearTapState()
            return
        }

        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
        clearTapState()
    }

    private func storeTapIfActive(
        tap: CFMachPort,
        source: CFRunLoopSource,
        runLoop: CFRunLoop,
        installResult: TapInstallResult
    ) -> Bool {
        tapLock.lock()
        defer { tapLock.unlock() }
        guard !installResult.isAbandoned else {
            return false
        }
        eventTap = tap
        runLoopSource = source
        tapRunLoop = runLoop
        return true
    }

    private func clearTapState() {
        tapLock.lock()
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
        tapLock.unlock()
    }

    private func currentTapState() -> (tap: CFMachPort?, source: CFRunLoopSource?, runLoop: CFRunLoop?) {
        tapLock.lock()
        defer { tapLock.unlock() }
        return (eventTap, runLoopSource, tapRunLoop)
    }

    private func isTapRunningOrInstalling() -> Bool {
        tapLock.lock()
        defer { tapLock.unlock() }
        return eventTap != nil || tapThread != nil
    }

    private func scheduleTapRecovery(type: CGEventType) {
        let reason = Self.name(for: type)
        let tap = currentTapState().tap
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.logStore.append("tap disabled: \(reason); re-enabled")
        }
    }

    private static func isKeyDown(_ keyCode: UInt16) -> Bool {
        CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode))
    }

    private static func eventMask(_ types: CGEventType...) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }

    private static func name(for type: CGEventType) -> String {
        switch type {
        case .keyDown: "keyDown"
        case .keyUp: "keyUp"
        case .flagsChanged: "flagsChanged"
        case .tapDisabledByTimeout: "tapDisabledByTimeout"
        case .tapDisabledByUserInput: "tapDisabledByUserInput"
        default: "event\(type.rawValue)"
        }
    }
}

private final class TapInstallResult {
    private let condition = NSCondition()
    private var result: (success: Bool, message: String)?
    private var abandoned = false

    var isAbandoned: Bool {
        condition.lock()
        defer { condition.unlock() }
        return abandoned
    }

    @discardableResult
    func finish(success: Bool, message: String) -> Bool {
        condition.lock()
        guard !abandoned else {
            condition.unlock()
            return false
        }
        result = (success, message)
        condition.broadcast()
        condition.unlock()
        return true
    }

    func wait(timeout: TimeInterval) -> (success: Bool, message: String) {
        let deadline = Date().addingTimeInterval(timeout)

        condition.lock()
        while result == nil && condition.wait(until: deadline) {}
        let value: (success: Bool, message: String)
        if let result {
            value = result
        } else {
            abandoned = true
            value = (false, "tap failed: install timed out on dedicated run loop")
        }
        condition.unlock()

        return value
    }
}
