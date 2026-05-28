import AppKit
import ApplicationServices

struct WindowScreenSnapshot: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
    let name: String?
    let scaleFactor: CGFloat?

    init(
        frame: CGRect,
        visibleFrame: CGRect,
        name: String? = nil,
        scaleFactor: CGFloat? = nil
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.name = name
        self.scaleFactor = scaleFactor
    }

    init(screen: NSScreen) {
        self.init(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            name: screen.localizedName,
            scaleFactor: screen.backingScaleFactor
        )
    }
}

enum DisplayFrameMapper {
    static func displayFrames(from snapshots: [WindowScreenSnapshot]) -> [DisplayFrame] {
        let coordinateAnchorIndex = coordinateAnchorIndex(in: snapshots)

        return snapshots.enumerated().map { index, snapshot in
            DisplayFrame(
                frame: snapshot.frame,
                visibleFrame: snapshot.visibleFrame,
                isCoordinateAnchor: index == coordinateAnchorIndex,
                identifier: snapshot.name,
                scaleFactor: snapshot.scaleFactor
            )
        }
    }

    static func usesFallbackAnchor(in snapshots: [WindowScreenSnapshot]) -> Bool {
        !snapshots.isEmpty && snapshots.firstIndex { $0.frame.origin == .zero } == nil
    }

    private static func coordinateAnchorIndex(in snapshots: [WindowScreenSnapshot]) -> Int? {
        snapshots.firstIndex { $0.frame.origin == .zero } ?? snapshots.indices.first
    }
}

final class WindowActor {
    private static let fullScreenAttribute = "AXFullScreen"
    private static let minimizedAttribute = kAXMinimizedAttribute

    private let logStore: LogStore

    init(logStore: LogStore) {
        self.logStore = logStore
    }

    func perform(_ intent: ShortcutIntent) {
        guard case .windowAction(let action, shortcutLabel: _) = intent else {
            return
        }

        runOnMain { [weak self] in
            self?.perform(action)
        }
    }

    private func perform(_ action: WindowAction) {
        logStore.append("action start windowAction=\(action.rawValue)")

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            logStore.append("action failed windowAction=\(action.rawValue) no frontmost app")
            return
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        let focusedWindowResult = focusedWindow(in: appElement)
        guard focusedWindowResult.error == .success, let window = focusedWindowResult.window else {
            logStore.append(
                "action failed windowAction=\(action.rawValue) no focused window axError=\(focusedWindowResult.error.rawValue)"
            )
            return
        }

        if readBoolAttribute(Self.fullScreenAttribute, from: window).value == true {
            logStore.append("action skipped windowAction=\(action.rawValue) fullscreen")
            return
        }

        if readBoolAttribute(Self.minimizedAttribute, from: window).value == true {
            logStore.append("action skipped windowAction=\(action.rawValue) minimized")
            return
        }

        let positionResult = readPointAttribute(kAXPositionAttribute, from: window)
        guard positionResult.error == .success, let positionAX = positionResult.point else {
            logStore.append(
                "action failed windowAction=\(action.rawValue) read position axError=\(positionResult.error.rawValue)"
            )
            return
        }

        let sizeResult = readSizeAttribute(kAXSizeAttribute, from: window)
        guard sizeResult.error == .success, let size = sizeResult.size else {
            logStore.append("action failed windowAction=\(action.rawValue) read size axError=\(sizeResult.error.rawValue)")
            return
        }

        let displays = displayFrames()
        let currentAXRect = CGRect(origin: positionAX, size: size)
        guard
            let currentAppKitRect = ScreenCoordinateConverter.axRectToAppKit(currentAXRect, in: displays),
            let display = ScreenCoordinateConverter.selectDisplay(for: currentAXRect, in: displays)
        else {
            logStore.append("action failed windowAction=\(action.rawValue) no selectable display")
            return
        }

        let targetAppKitRect = action.targetRect(in: display.visibleFrame)
        let targetAppKitTopLeft = CGPoint(x: targetAppKitRect.minX, y: targetAppKitRect.maxY)
        guard let targetAXOrigin = ScreenCoordinateConverter.appKitPointToAX(targetAppKitTopLeft, in: displays) else {
            logStore.append("action failed windowAction=\(action.rawValue) no selectable display")
            return
        }

        let axInitialSizeResult = setSize(targetAppKitRect.size, on: window)
        let axPositionResult = setPosition(targetAXOrigin, on: window)
        // Re-apply size after moving; the first write can be clamped at the old origin.
        let axFinalSizeResult = setSize(targetAppKitRect.size, on: window)
        let resultVerb = resultVerb(
            initialSizeResult: axInitialSizeResult,
            positionResult: axPositionResult,
            finalSizeResult: axFinalSizeResult
        )
        logStore.append(
            "\(resultVerb) windowAction=\(action.rawValue) currentAppKit=\(format(currentAppKitRect)) display=\(format(display)) rectAppKit=\(format(targetAppKitRect)) originAX=\(format(targetAXOrigin)) axInitialSizeResult=\(axInitialSizeResult.rawValue) axPositionResult=\(axPositionResult.rawValue) axFinalSizeResult=\(axFinalSizeResult.rawValue)"
        )
    }

    private func displayFrames() -> [DisplayFrame] {
        let snapshots = NSScreen.screens.map(WindowScreenSnapshot.init(screen:))
        if DisplayFrameMapper.usesFallbackAnchor(in: snapshots), let coordinateAnchorSnapshot = snapshots.first {
            logStore.append(
                "display warning coordinateAnchor=fallback display=\(coordinateAnchorSnapshot.name ?? "unknown") frame=\(format(coordinateAnchorSnapshot.frame))"
            )
        }

        return DisplayFrameMapper.displayFrames(from: snapshots)
    }

    private func focusedWindow(in appElement: AXUIElement) -> (window: AXUIElement?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        guard error == .success, let value else {
            return (nil, error)
        }

        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return (nil, .failure)
        }
        return ((value as! AXUIElement), error)
    }

    private func readPointAttribute(_ attribute: String, from element: AXUIElement) -> (point: CGPoint?, error: AXError) {
        guard let result = copyAXValueAttribute(attribute, from: element, expectedType: .cgPoint) else {
            return (nil, .failure)
        }

        guard result.error == .success, let value = result.value else {
            return (nil, result.error)
        }

        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else {
            return (nil, .failure)
        }
        return (point, .success)
    }

    private func readSizeAttribute(_ attribute: String, from element: AXUIElement) -> (size: CGSize?, error: AXError) {
        guard let result = copyAXValueAttribute(attribute, from: element, expectedType: .cgSize) else {
            return (nil, .failure)
        }

        guard result.error == .success, let value = result.value else {
            return (nil, result.error)
        }

        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else {
            return (nil, .failure)
        }
        return (size, .success)
    }

    private func readBoolAttribute(_ attribute: String, from element: AXUIElement) -> (value: Bool?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return (nil, error)
        }

        return (value as? Bool, .success)
    }

    private func copyAXValueAttribute(
        _ attribute: String,
        from element: AXUIElement,
        expectedType: AXValueType
    ) -> (value: AXValue?, error: AXError)? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return (nil, error)
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == expectedType else {
            return nil
        }
        return (axValue, .success)
    }

    private func setSize(_ size: CGSize, on window: AXUIElement) -> AXError {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    private func setPosition(_ position: CGPoint, on window: AXUIElement) -> AXError {
        var mutablePosition = position
        guard let value = AXValueCreate(.cgPoint, &mutablePosition) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func resultVerb(
        initialSizeResult: AXError,
        positionResult: AXError,
        finalSizeResult: AXError
    ) -> String {
        switch (initialSizeResult == .success, positionResult == .success, finalSizeResult == .success) {
        case (_, true, true):
            "action applied"
        case (false, false, false):
            "action failed"
        default:
            "action partial"
        }
    }

    private func format(_ display: DisplayFrame) -> String {
        "{id=\(display.identifier ?? "unknown"),frame=\(format(display.frame)),visibleFrame=\(format(display.visibleFrame)),coordinateAnchor=\(display.isCoordinateAnchor)}"
    }

    private func format(_ rect: CGRect) -> String {
        "{\(format(rect.origin.x)),\(format(rect.origin.y)),\(format(rect.size.width)),\(format(rect.size.height))}"
    }

    private func format(_ point: CGPoint) -> String {
        "{\(format(point.x)),\(format(point.y))}"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
