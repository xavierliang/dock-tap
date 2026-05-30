import Foundation
import IOKit
import IOKit.pwr_mgt

/// 监听 MacBook 合盖/开盖（clamshell）状态变化。
protocol LidStateObserving: AnyObject {
    /// 状态变化回调，参数 true 表示已合盖。回调在主线程触发。
    var onLidStateChanged: ((Bool) -> Void)? { get set }
    /// 一次性查询当前是否合盖（读 IORegistry 的权威状态）。
    func isLidCurrentlyClosed() -> Bool
    func start()
    func stop()
}

final class LidStateObserver: LidStateObserving {
    var onLidStateChanged: ((Bool) -> Void)?

    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var rootDomain: io_service_t = 0
    private var lastReportedClosed: Bool?

    deinit {
        stop()
    }

    func start() {
        guard notificationPort == nil else {
            return
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            return
        }
        rootDomain = service

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            IOObjectRelease(service)
            rootDomain = 0
            return
        }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var notification: io_object_t = 0
        let result = IOServiceAddInterestNotification(
            port,
            service,
            kIOGeneralInterest,
            { refcon, _, _, _ in
                guard let refcon else { return }
                let observer = Unmanaged<LidStateObserver>.fromOpaque(refcon).takeUnretainedValue()
                observer.handleInterest()
            },
            refcon,
            &notification
        )

        guard result == KERN_SUCCESS else {
            stop()
            return
        }
        notifier = notification

        // 对齐初始状态，避免错过监听注册前已发生的合盖。
        lastReportedClosed = isLidCurrentlyClosed()
    }

    func stop() {
        if notifier != 0 {
            IOObjectRelease(notifier)
            notifier = 0
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        if rootDomain != 0 {
            IOObjectRelease(rootDomain)
            rootDomain = 0
        }
        lastReportedClosed = nil
    }

    func isLidCurrentlyClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            return false
        }
        defer { IOObjectRelease(service) }
        guard let prop = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return false
        }
        let value = prop.takeRetainedValue()
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return false
        }
        // swiftlint:disable:next force_cast
        return CFBooleanGetValue((value as! CFBoolean))
    }

    /// `kIOPMMessageClamshellStateChange` 宏在 Swift 中不可用（SDK 标 "structure not
    /// supported"），故不按 messageType 过滤。IOPMrootDomain 的 general-interest 消息
    /// 不频繁，每次回调重读权威 `AppleClamshellState` 并去重即可——比解析 bitfield 更稳。
    private func handleInterest() {
        let closed = isLidCurrentlyClosed()
        guard closed != lastReportedClosed else {
            return
        }
        lastReportedClosed = closed
        onLidStateChanged?(closed)
    }
}
