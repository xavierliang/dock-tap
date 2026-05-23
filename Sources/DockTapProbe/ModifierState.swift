import CoreGraphics

struct ModifierSnapshot: Equatable {
    var leftOption = false
    var rightOption = false
    var leftShift = false
    var rightShift = false
    var leftCommand = false
    var rightCommand = false
    var leftControl = false
    var rightControl = false
    var capsLock = false
    var function = false

    var hasRejectingExtraModifier: Bool {
        rightOption ||
            leftShift || rightShift ||
            leftCommand || rightCommand ||
            leftControl || rightControl
    }

    var shortDescription: String {
        [
            "LOpt:\(bit(leftOption))",
            "ROpt:\(bit(rightOption))",
            "Shift:\(bit(leftShift || rightShift))",
            "Cmd:\(bit(leftCommand || rightCommand))",
            "Ctrl:\(bit(leftControl || rightControl))",
            "Caps:\(bit(capsLock))",
            "Fn:\(bit(function))"
        ].joined(separator: " ")
    }

    private func bit(_ value: Bool) -> String {
        value ? "1" : "0"
    }
}

struct ModifierChange: Equatable {
    let keyCode: UInt16
    let isDown: Bool
}

struct ModifierState {
    private(set) var snapshot = ModifierSnapshot()

    @discardableResult
    mutating func setPhysicalKey(_ keyCode: UInt16, isDown: Bool) -> ModifierChange? {
        let old = snapshot
        apply(keyCode, isDown: isDown)
        return old == snapshot ? nil : ModifierChange(keyCode: keyCode, isDown: isDown)
    }

    @discardableResult
    mutating func resync(readKeyDown: (UInt16) -> Bool) -> [ModifierChange] {
        KeyCodes.trackedModifiers.compactMap { keyCode in
            setPhysicalKey(keyCode, isDown: readKeyDown(keyCode))
        }
    }

    private mutating func apply(_ keyCode: UInt16, isDown: Bool) {
        switch keyCode {
        case KeyCodes.leftOption:
            snapshot.leftOption = isDown
        case KeyCodes.rightOption:
            snapshot.rightOption = isDown
        case KeyCodes.leftShift:
            snapshot.leftShift = isDown
        case KeyCodes.rightShift:
            snapshot.rightShift = isDown
        case KeyCodes.leftCommand:
            snapshot.leftCommand = isDown
        case KeyCodes.rightCommand:
            snapshot.rightCommand = isDown
        case KeyCodes.leftControl:
            snapshot.leftControl = isDown
        case KeyCodes.rightControl:
            snapshot.rightControl = isDown
        case KeyCodes.capsLock:
            snapshot.capsLock = isDown
        case KeyCodes.function:
            snapshot.function = isDown
        default:
            break
        }
    }
}
