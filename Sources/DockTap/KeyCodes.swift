import CoreGraphics

enum KeyCodes {
    static let one: UInt16 = 18
    static let two: UInt16 = 19
    static let three: UInt16 = 20
    static let four: UInt16 = 21
    static let five: UInt16 = 23
    static let six: UInt16 = 22
    static let seven: UInt16 = 26
    static let eight: UInt16 = 28
    static let nine: UInt16 = 25
    static let zero: UInt16 = 29
    static let backtick: UInt16 = 50
    static let returnKey: UInt16 = 36
    static let space: UInt16 = 49
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126

    static let leftCommand: UInt16 = 55
    static let rightCommand: UInt16 = 54
    static let leftShift: UInt16 = 56
    static let rightShift: UInt16 = 60
    static let leftOption: UInt16 = 58
    static let rightOption: UInt16 = 61
    static let leftControl: UInt16 = 59
    static let rightControl: UInt16 = 62
    static let capsLock: UInt16 = 57
    static let function: UInt16 = 63

    static let trackedModifiers: [UInt16] = [
        leftCommand,
        rightCommand,
        leftShift,
        rightShift,
        leftOption,
        rightOption,
        leftControl,
        rightControl,
        capsLock,
        function
    ]

    static func label(for keyCode: UInt16) -> String {
        switch keyCode {
        case one: "1"
        case two: "2"
        case three: "3"
        case four: "4"
        case five: "5"
        case six: "6"
        case seven: "7"
        case eight: "8"
        case nine: "9"
        case zero: "0"
        case backtick: "`"
        case returnKey: "Return"
        case space: "Space"
        case leftArrow: "leftArrow"
        case rightArrow: "rightArrow"
        case downArrow: "downArrow"
        case upArrow: "upArrow"
        case leftOption: "leftOption"
        case rightOption: "rightOption"
        case leftShift: "leftShift"
        case rightShift: "rightShift"
        case leftCommand: "leftCommand"
        case rightCommand: "rightCommand"
        case leftControl: "leftControl"
        case rightControl: "rightControl"
        case capsLock: "capsLock"
        case function: "fn"
        default: "key\(keyCode)"
        }
    }
}
