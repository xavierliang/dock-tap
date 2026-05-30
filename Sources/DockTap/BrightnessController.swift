import CoreGraphics
import Foundation

/// 内置屏亮度读写的高层接口，供 `ClosedLidKeepAwakeController` 使用。
/// 所有调用在底层 API 不可用时安全降级（读返回 nil / 写返回 false），
/// 绝不让亮度功能的失败影响 keep-awake 主功能。
protocol BrightnessControlling: AnyObject {
    /// 内置屏当前亮度 0.0–1.0；读不到返回 nil。
    func currentInternalBrightness() -> Double?
    /// 设置内置屏亮度（自动 clamp 到 0.0–1.0）；返回是否成功。
    @discardableResult
    func setInternalBrightness(_ value: Double) -> Bool
}

/// 单个私有 API 家族的亮度后端抽象。允许测试注入 fake，
/// 也允许生产期按"能否真正读出有效值"在多个后端间择优。
protocol DisplayBrightnessBackend: AnyObject {
    var name: String { get }
    func brightness(for id: CGDirectDisplayID) -> Double?
    func setBrightness(_ value: Double, for id: CGDirectDisplayID) -> Bool
}

/// 定位内置屏的 CGDirectDisplayID。
protocol BuiltinDisplayLocating {
    func builtinDisplayID() -> CGDirectDisplayID?
}

// MARK: - Controller

final class BrightnessController: BrightnessControlling {
    private let locator: BuiltinDisplayLocating
    private let backends: [DisplayBrightnessBackend]
    private let log: (String) -> Void

    /// 已选定的后端缓存。一旦某后端能读出有效值就固定用它，避免每次重选。
    private var selectedBackend: DisplayBrightnessBackend?
    private var loggedNoBackend = false

    init(
        locator: BuiltinDisplayLocating = CoreGraphicsBuiltinDisplayLocator(),
        backends: [DisplayBrightnessBackend] = BrightnessController.defaultBackends(),
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.locator = locator
        self.backends = backends
        self.log = log
    }

    /// 生产默认后端，按 Apple Silicon 实测可用性排序：
    /// DisplayServices 优先（M 系列 + 新 macOS 主力），CoreDisplay 兜底
    /// （macOS 26 上实测 get 返回 -1，会在 resolveBackend 时被自动跳过）。
    static func defaultBackends() -> [DisplayBrightnessBackend] {
        var result: [DisplayBrightnessBackend] = []
        if let ds = DisplayServicesBrightnessBackend() {
            result.append(ds)
        }
        if let cd = CoreDisplayBrightnessBackend() {
            result.append(cd)
        }
        return result
    }

    func currentInternalBrightness() -> Double? {
        guard let id = locator.builtinDisplayID() else {
            return nil
        }
        guard let backend = resolveBackend(for: id) else {
            return nil
        }
        return backend.brightness(for: id)
    }

    @discardableResult
    func setInternalBrightness(_ value: Double) -> Bool {
        guard let id = locator.builtinDisplayID() else {
            return false
        }
        guard let backend = resolveBackend(for: id) else {
            return false
        }
        let clamped = max(0.0, min(1.0, value))
        let ok = backend.setBrightness(clamped, for: id)
        if !ok {
            log("brightness set failed via \(backend.name)")
        }
        return ok
    }

    /// 仅 dlsym 成功不足以认定后端可用——必须能真正读出有效值。
    private func resolveBackend(for id: CGDirectDisplayID) -> DisplayBrightnessBackend? {
        if let selectedBackend {
            return selectedBackend
        }
        for backend in backends where backend.brightness(for: id) != nil {
            selectedBackend = backend
            log("brightness backend selected=\(backend.name)")
            return backend
        }
        if !loggedNoBackend {
            loggedNoBackend = true
            log("brightness no working backend; dimming disabled")
        }
        return nil
    }
}

// MARK: - 内置屏定位（生产实现）

/// 用 CGDisplayIsBuiltin 显式筛内置屏；接外接屏时 main display 可能不是内置屏，
/// 故不使用 CGMainDisplayID()。
struct CoreGraphicsBuiltinDisplayLocator: BuiltinDisplayLocating {
    func builtinDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return nil
        }
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }
}

// MARK: - dlopen/dlsym 辅助

private func openFramework(_ candidates: [String]) -> UnsafeMutableRawPointer? {
    for path in candidates {
        if let handle = dlopen(path, RTLD_LAZY) {
            return handle
        }
    }
    return nil
}

// MARK: - DisplayServices 后端（优先）

/// DisplayServicesGetBrightness/SetBrightness：int Fn(CGDirectDisplayID, float[*])。
/// macOS 11+ Apple Silicon 主力。
final class DisplayServicesBrightnessBackend: DisplayBrightnessBackend {
    let name = "DisplayServices"

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getFn: GetFn
    private let setFn: SetFn

    init?() {
        guard let handle = openFramework([
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            "DisplayServices.framework/DisplayServices",
        ]),
            let getSym = dlsym(handle, "DisplayServicesGetBrightness"),
            let setSym = dlsym(handle, "DisplayServicesSetBrightness")
        else {
            return nil
        }
        getFn = unsafeBitCast(getSym, to: GetFn.self)
        setFn = unsafeBitCast(setSym, to: SetFn.self)
    }

    func brightness(for id: CGDirectDisplayID) -> Double? {
        var value: Float = -1
        guard getFn(id, &value) == 0, value >= 0 else {
            return nil
        }
        return Double(value)
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) -> Bool {
        setFn(id, Float(value)) == 0
    }
}

// MARK: - CoreDisplay 后端（兜底）

/// CoreDisplay_Display_GetUserBrightness/SetUserBrightness：double 签名。
/// 旧路径；macOS 26 上 get 返回 -1，会被择优逻辑自动跳过。
final class CoreDisplayBrightnessBackend: DisplayBrightnessBackend {
    let name = "CoreDisplay"

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Double) -> Int32

    private let getFn: GetFn
    private let setFn: SetFn

    init?() {
        guard let handle = openFramework([
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            "CoreDisplay.framework/CoreDisplay",
        ]),
            let getSym = dlsym(handle, "CoreDisplay_Display_GetUserBrightness"),
            let setSym = dlsym(handle, "CoreDisplay_Display_SetUserBrightness")
        else {
            return nil
        }
        getFn = unsafeBitCast(getSym, to: GetFn.self)
        setFn = unsafeBitCast(setSym, to: SetFn.self)
    }

    func brightness(for id: CGDirectDisplayID) -> Double? {
        var value: Double = -1
        guard getFn(id, &value) == 0, value >= 0 else {
            return nil
        }
        return value
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) -> Bool {
        setFn(id, value) == 0
    }
}
