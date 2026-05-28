import CoreGraphics
import Foundation

enum EventTapReadiness: Equatable {
    case stopped
    case installing
    case ready
    case recovering
}

final class EventTapController {
    private let logStore: LogStore
    private let onShortcut: (ShortcutIntent) -> Void
    private let decider = KeyEventDecider()
    private let inputLock = NSLock()
    private let tapLock = NSLock()

    private var slotSnapshot = DockSlotSnapshot.empty
    private var triggerModifierPreset = TriggerModifierPreset.defaultPreset
    private var windowActionsEnabled = false
    private var modifierState = ModifierState()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var tapReadiness = EventTapReadiness.stopped
    private var tapGeneration: UInt64 = 0

    var onReadinessChanged: ((EventTapReadiness) -> Void)?
    var onReconcileRequested: (() -> Void)?

    var readiness: EventTapReadiness {
        tapLock.lock()
        defer { tapLock.unlock() }
        return tapReadiness
    }

    var isReady: Bool {
        readiness == .ready
    }

    init(logStore: LogStore, onShortcut: @escaping (ShortcutIntent) -> Void) {
        self.logStore = logStore
        self.onShortcut = onShortcut
    }

    func updateSlotSnapshot(_ snapshot: DockSlotSnapshot) {
        inputLock.lock()
        slotSnapshot = snapshot
        inputLock.unlock()
    }

    func updateTriggerModifierPreset(_ preset: TriggerModifierPreset) {
        inputLock.lock()
        triggerModifierPreset = preset
        inputLock.unlock()
    }

    func updateWindowActionsEnabled(_ isEnabled: Bool) {
        inputLock.lock()
        windowActionsEnabled = isEnabled
        inputLock.unlock()
    }

    func install() -> Bool {
        if readiness == .recovering {
            stop()
        }

        guard let generation = reserveTapInstall() else {
            let currentReadiness = readiness
            if currentReadiness == .installing {
                logStore.append("tap install already in progress")
            } else {
                logStore.append("tap already installed")
            }
            return currentReadiness == .ready
        }

        let installResult = TapInstallResult()
        let thread = Thread { [weak self] in
            guard let self else {
                installResult.finish(success: false, message: "tap failed: controller was released before install")
                return
            }
            self.runTapThread(installResult: installResult, generation: generation)
        }
        thread.name = "DockTap Event Tap"

        guard storeTapThread(thread, generation: generation) else {
            installResult.finish(success: false, message: "tap failed: install was cancelled before thread start")
            return false
        }
        thread.start()

        let result = installResult.wait(timeout: 2.0)
        logStore.append(result.message)
        if !result.success {
            clearTapState(generation: generation, invalidateGeneration: true)
        }
        return result.success && isReady
    }

    func stop() {
        let state = currentTapState()
        guard let tap = state.tap else {
            if state.readiness != .stopped || state.hasThread {
                clearTapState(generation: state.generation, invalidateGeneration: true)
                logStore.append("tap stopped")
            }
            return
        }

        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoop = state.runLoop, let source = state.source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
        CFMachPortInvalidate(tap)
        clearTapState(generation: state.generation, invalidateGeneration: true)
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

        switch type {
        case .flagsChanged:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let isDown = Self.isKeyDown(keyCode)
            modifierState.setPhysicalKey(keyCode, isDown: isDown)
            return Unmanaged.passUnretained(event)

        case .keyDown, .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            modifierState.resync(readKeyDown: Self.isKeyDown)
            let input = currentInputSnapshot()
            let decision = decider.decide(
                kind: type == .keyDown ? .keyDown : .keyUp,
                keyCode: keyCode,
                modifiers: modifierState.snapshot,
                triggerModifier: input.triggerModifierPreset,
                slots: input.slotSnapshot,
                windowActionsEnabled: input.windowActionsEnabled
            )
            if let intent = decision.intent {
                enqueueShortcut(intent)
            }
            return decision.consumesEvent ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func enqueueShortcut(_ intent: ShortcutIntent) {
        DispatchQueue.main.async { [onShortcut] in
            onShortcut(intent)
        }
    }

    private func currentInputSnapshot() -> (
        slotSnapshot: DockSlotSnapshot,
        triggerModifierPreset: TriggerModifierPreset,
        windowActionsEnabled: Bool
    ) {
        inputLock.lock()
        defer { inputLock.unlock() }
        return (slotSnapshot, triggerModifierPreset, windowActionsEnabled)
    }

    private func runTapThread(installResult: TapInstallResult, generation: UInt64) {
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
        guard !installResult.isAbandoned, isCurrentTapGeneration(generation) else {
            CFMachPortInvalidate(tap)
            installResult.finish(success: false, message: "tap failed: install was cancelled before activation")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            installResult.finish(success: false, message: "tap failed: could not create run loop source")
            return
        }
        guard !installResult.isAbandoned, isCurrentTapGeneration(generation) else {
            CFMachPortInvalidate(tap)
            installResult.finish(success: false, message: "tap failed: install was cancelled before activation")
            return
        }

        guard let runLoop = CFRunLoopGetCurrent() else {
            CFMachPortInvalidate(tap)
            installResult.finish(success: false, message: "tap failed: could not get current run loop")
            return
        }
        guard !installResult.isAbandoned, isCurrentTapGeneration(generation) else {
            CFMachPortInvalidate(tap)
            installResult.finish(success: false, message: "tap failed: install was cancelled before activation")
            return
        }

        guard storeTapIfActive(tap: tap, source: source, runLoop: runLoop, installResult: installResult, generation: generation) else {
            CFMachPortInvalidate(tap)
            installResult.finish(success: false, message: "tap failed: install was cancelled before activation")
            return
        }

        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard setReadiness(.ready, generation: generation) else {
            CFMachPortInvalidate(tap)
            installResult.finish(success: false, message: "tap failed: install was cancelled before activation")
            return
        }
        guard installResult.finish(
            success: true,
            message: "tap installed: active session keyboard tap enabled on dedicated run loop"
        ) else {
            CFMachPortInvalidate(tap)
            clearTapState(generation: generation, invalidateGeneration: true)
            return
        }

        CFRunLoopRun()
        clearTapState(generation: generation)
    }

    private func storeTapIfActive(
        tap: CFMachPort,
        source: CFRunLoopSource,
        runLoop: CFRunLoop,
        installResult: TapInstallResult,
        generation: UInt64
    ) -> Bool {
        tapLock.lock()
        defer { tapLock.unlock() }
        guard !installResult.isAbandoned, tapGeneration == generation, tapReadiness == .installing else {
            return false
        }
        eventTap = tap
        runLoopSource = source
        tapRunLoop = runLoop
        return true
    }

    private func reserveTapInstall() -> UInt64? {
        var shouldNotify = false
        let generation: UInt64?
        tapLock.lock()
        if tapReadiness == .ready || tapReadiness == .installing || eventTap != nil || tapThread != nil {
            generation = nil
        } else {
            tapGeneration &+= 1
            generation = tapGeneration
            tapReadiness = .installing
            shouldNotify = true
        }
        tapLock.unlock()

        if shouldNotify {
            notifyReadinessChanged(.installing)
        }
        return generation
    }

    private func storeTapThread(_ thread: Thread, generation: UInt64) -> Bool {
        tapLock.lock()
        defer { tapLock.unlock() }
        guard tapGeneration == generation, tapReadiness == .installing else {
            return false
        }
        tapThread = thread
        return true
    }

    private func clearTapState(
        generation expectedGeneration: UInt64? = nil,
        readiness newReadiness: EventTapReadiness = .stopped,
        invalidateGeneration: Bool = false
    ) {
        var shouldNotify = false
        tapLock.lock()
        if let expectedGeneration, tapGeneration != expectedGeneration {
            tapLock.unlock()
            return
        }
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
        if invalidateGeneration {
            tapGeneration &+= 1
        }
        if tapReadiness != newReadiness {
            tapReadiness = newReadiness
            shouldNotify = true
        }
        tapLock.unlock()

        if shouldNotify {
            notifyReadinessChanged(newReadiness)
        }
    }

    private func currentTapState() -> (
        tap: CFMachPort?,
        source: CFRunLoopSource?,
        runLoop: CFRunLoop?,
        generation: UInt64,
        readiness: EventTapReadiness,
        hasThread: Bool
    ) {
        tapLock.lock()
        defer { tapLock.unlock() }
        return (eventTap, runLoopSource, tapRunLoop, tapGeneration, tapReadiness, tapThread != nil)
    }

    private func isCurrentTapGeneration(_ generation: UInt64) -> Bool {
        tapLock.lock()
        defer { tapLock.unlock() }
        return tapGeneration == generation
    }

    @discardableResult
    private func setReadiness(_ newReadiness: EventTapReadiness, generation expectedGeneration: UInt64? = nil) -> Bool {
        var shouldNotify = false
        tapLock.lock()
        if let expectedGeneration, tapGeneration != expectedGeneration {
            tapLock.unlock()
            return false
        }
        if tapReadiness != newReadiness {
            tapReadiness = newReadiness
            shouldNotify = true
        }
        tapLock.unlock()

        if shouldNotify {
            notifyReadinessChanged(newReadiness)
        }
        return true
    }

    private func notifyReadinessChanged(_ readiness: EventTapReadiness) {
        DispatchQueue.main.async { [weak self] in
            self?.onReadinessChanged?(readiness)
        }
    }

    private func scheduleTapRecovery(type: CGEventType) {
        let reason = Self.name(for: type)
        let state = currentTapState()
        guard state.tap != nil else {
            return
        }
        _ = setReadiness(.recovering, generation: state.generation)
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.logStore.append("tap disabled: \(reason); requesting health reconcile")
            self.onReconcileRequested?()
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
