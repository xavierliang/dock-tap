import Foundation

enum ProbeEventResult: String, Equatable {
    case consumed
    case passThrough = "pass-through"
    case stateOnly = "state-only"
}

struct ProbeEventRecord {
    let timestamp: TimeInterval
    let eventType: String
    let keyCode: UInt16?
    let modifiers: ModifierSnapshot
    let frontmostBundleID: String?
    let matchedRuleID: String?
    let result: ProbeEventResult

    func message() -> String {
        let key = keyCode.map { "\(KeyCodes.label(for: $0))(\($0))" } ?? "-"
        let frontmost = frontmostBundleID ?? "-"
        let rule = matchedRuleID ?? "-"
        return "\(format(timestamp)) \(eventType) key=\(key) mods=[\(modifiers.shortDescription)] frontmost=\(frontmost) rule=\(rule) result=\(result.rawValue)"
    }

    private func format(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSinceReferenceDate: timestamp)
        return LogStore.timestampFormatter.string(from: date)
    }
}

struct LogEntry: Equatable {
    let text: String
}

final class LogStore {
    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var onChange: (([LogEntry]) -> Void)?

    private let limit: Int
    private(set) var entries: [LogEntry] = []

    init(limit: Int = 400) {
        self.limit = limit
    }

    func append(_ text: String) {
        runOnMain { [weak self] in
            self?.appendOnMain(text)
        }
    }

    func append(_ record: ProbeEventRecord) {
        runOnMain { [weak self] in
            self?.appendOnMain(record.message())
        }
    }

    private func appendOnMain(_ text: String) {
        entries.append(LogEntry(text: text))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        onChange?(entries)
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
