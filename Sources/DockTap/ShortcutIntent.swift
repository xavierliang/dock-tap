import Foundation

enum ShortcutIntent: Equatable {
    case dockSlot(DockSlotTarget, shortcutLabel: String)
    case finder(shortcutLabel: String)
    case windowAction(WindowAction, shortcutLabel: String)
    case keepAwake(KeepAwakeShortcut, shortcutLabel: String)

    var label: String {
        switch self {
        case .dockSlot(_, let shortcutLabel):
            shortcutLabel
        case .finder(let shortcutLabel):
            shortcutLabel
        case .windowAction(_, let shortcutLabel):
            shortcutLabel
        case .keepAwake(_, let shortcutLabel):
            shortcutLabel
        }
    }
}

enum KeepAwakeShortcut: Equatable {
    case oneHour
    case indefinite
    case stop

    var shortcutKeyLabel: String {
        switch self {
        case .oneHour:
            "A"
        case .indefinite:
            "S"
        case .stop:
            "D"
        }
    }
}

struct DockSlotTarget: Equatable {
    let id: String
    let shortcutIndex: Int
    let dockOrdinal: Int
    let appURL: URL
    let displayName: String
    let bundleIdentifier: String?
    let isMissing: Bool

    var logDescription: String {
        "shortcutIndex=\(shortcutIndex) dockOrdinal=\(dockOrdinal) app=\"\(displayName)\""
    }
}

struct DockSlotSnapshot: Equatable {
    static let empty = DockSlotSnapshot(targetsByShortcutIndex: [:])

    private let targetsByShortcutIndex: [Int: DockSlotTarget]

    init(targetsByShortcutIndex: [Int: DockSlotTarget]) {
        self.targetsByShortcutIndex = targetsByShortcutIndex
    }

    init(targets: [DockSlotTarget]) {
        targetsByShortcutIndex = Dictionary(uniqueKeysWithValues: targets.map { ($0.shortcutIndex, $0) })
    }

    func target(shortcutIndex: Int) -> DockSlotTarget? {
        targetsByShortcutIndex[shortcutIndex]
    }
}
