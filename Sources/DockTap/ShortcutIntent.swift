import Foundation

enum ShortcutIntent: Equatable {
    case dockSlot(DockSlotTarget, shortcutLabel: String)
    case finder(shortcutLabel: String)

    var label: String {
        switch self {
        case .dockSlot(_, let shortcutLabel):
            shortcutLabel
        case .finder(let shortcutLabel):
            shortcutLabel
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
