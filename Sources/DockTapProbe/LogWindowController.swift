import AppKit

final class LogWindowController: NSWindowController {
    private let textView = NSTextView()
    private let logStore: LogStore

    init(logStore: LogStore) {
        self.logStore = logStore

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 920, height: 460))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        scrollView.documentView = textView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dock Tap Probe Logs"
        window.contentView = scrollView
        window.center()

        super.init(window: window)

        logStore.onChange = { [weak self] entries in
            self?.render(entries)
        }
        render(logStore.entries)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func render(_ entries: [LogEntry]) {
        textView.string = entries.map(\.text).joined(separator: "\n")
        textView.scrollToEndOfDocument(nil)
    }
}
