import Foundation

enum ShortcutIntent: Equatable {
    case dockSlot(DockSlotTarget)
    case finder

    var label: String {
        switch self {
        case .dockSlot(let target):
            target.shortcutLabel
        case .finder:
            "leftOption+`"
        }
    }
}

struct DockSlotTarget: Equatable {
    let id: String
    let shortcutLabel: String
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
