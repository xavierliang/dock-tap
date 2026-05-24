import Foundation

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
            let timestamp = Self.timestampFormatter.string(from: Date())
            self?.appendOnMain("\(timestamp) \(text)")
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
