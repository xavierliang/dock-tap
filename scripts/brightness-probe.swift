#!/usr/bin/env swift
//
// brightness-probe.swift — Step 0 实测用的内置屏亮度探针
//
// 用途：在不引入第三方依赖的前提下，读/设 MacBook 内置屏亮度。
// 通过 dlopen/dlsym 动态解析 CoreDisplay 的半公开符号
// （CoreDisplay_Display_GetUserBrightness / _SetUserBrightness），
// 这与产品代码 BrightnessController 计划使用的同一套机制一致，
// 因此本探针验证的就是真实落地路径。
//
// 用法：
//   swift scripts/brightness-probe.swift get          # 打印内置屏当前亮度 (0.0–1.0)
//   swift scripts/brightness-probe.swift set 0.0      # 设内置屏亮度
//   swift scripts/brightness-probe.swift id           # 打印内置屏 CGDirectDisplayID 及诊断
//
// 退出码：0 成功；1 用法错误；2 找不到内置屏；3 符号解析失败；4 读/设失败。

import CoreGraphics
import Foundation

// MARK: - 内置屏定位

/// 返回内置屏的 CGDirectDisplayID。接外接屏时 main display 可能不是内置屏，
/// 所以用 CGDisplayIsBuiltin 显式筛选，而不是 CGMainDisplayID()。
func builtinDisplayID() -> CGDirectDisplayID? {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
        return nil
    }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
        return nil
    }
    for id in ids where CGDisplayIsBuiltin(id) != 0 {
        return id
    }
    return nil
}

// MARK: - 亮度符号动态解析
//
// 两套候选后端，按 Apple Silicon 实测可用性优先：
//   1. DisplayServices (PrivateFrameworks)：float 签名，M 系列 + 新 macOS 的主力。
//   2. CoreDisplay：Double 签名，旧路径；在 macOS 26 上实测 Get 失效（返回 -1）。
// 产品代码 BrightnessController 将复用同样的"优先 DisplayServices、回退 CoreDisplay、
// 全失败降级 no-op"策略。

typealias DSGetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias DSSetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
typealias CDGetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>) -> Int32
typealias CDSetFn = @convention(c) (CGDirectDisplayID, Double) -> Int32

/// 统一的亮度后端：get 返回 0.0–1.0 或 nil；set 返回是否成功。
struct BrightnessBackend {
    let name: String
    let get: (CGDirectDisplayID) -> Double?
    let set: (CGDirectDisplayID, Double) -> Bool
}

func loadDisplayServicesBackend() -> BrightnessBackend? {
    let candidates = [
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        "DisplayServices.framework/DisplayServices",
    ]
    var handle: UnsafeMutableRawPointer?
    for path in candidates {
        handle = dlopen(path, RTLD_LAZY)
        if handle != nil { break }
    }
    guard let handle,
          let getSym = dlsym(handle, "DisplayServicesGetBrightness"),
          let setSym = dlsym(handle, "DisplayServicesSetBrightness") else {
        return nil
    }
    let getFn = unsafeBitCast(getSym, to: DSGetFn.self)
    let setFn = unsafeBitCast(setSym, to: DSSetFn.self)
    return BrightnessBackend(
        name: "DisplayServices",
        get: { id in
            var v: Float = -1
            return getFn(id, &v) == 0 && v >= 0 ? Double(v) : nil
        },
        set: { id, value in setFn(id, Float(value)) == 0 }
    )
}

func loadCoreDisplayBackend() -> BrightnessBackend? {
    let candidates = [
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
        "CoreDisplay.framework/CoreDisplay",
    ]
    var handle: UnsafeMutableRawPointer?
    for path in candidates {
        handle = dlopen(path, RTLD_LAZY)
        if handle != nil { break }
    }
    guard let handle,
          let getSym = dlsym(handle, "CoreDisplay_Display_GetUserBrightness"),
          let setSym = dlsym(handle, "CoreDisplay_Display_SetUserBrightness") else {
        return nil
    }
    let getFn = unsafeBitCast(getSym, to: CDGetFn.self)
    let setFn = unsafeBitCast(setSym, to: CDSetFn.self)
    return BrightnessBackend(
        name: "CoreDisplay",
        get: { id in
            var v: Double = -1
            return getFn(id, &v) == 0 && v >= 0 ? v : nil
        },
        set: { id, value in setFn(id, value) == 0 }
    )
}

/// 选择第一个能真正读出亮度的后端（仅 dlsym 成功不够，Get 必须返回有效值）。
func loadBrightnessBackend(for id: CGDirectDisplayID) -> BrightnessBackend? {
    for loader in [loadDisplayServicesBackend, loadCoreDisplayBackend] {
        if let backend = loader(), backend.get(id) != nil {
            return backend
        }
    }
    return nil
}

// MARK: - 命令

func runGet() -> Int32 {
    guard let id = builtinDisplayID() else {
        FileHandle.standardError.write(Data("probe: no builtin display found\n".utf8))
        return 2
    }
    guard let backend = loadBrightnessBackend(for: id) else {
        FileHandle.standardError.write(Data("probe: no working brightness backend\n".utf8))
        return 3
    }
    guard let value = backend.get(id) else {
        FileHandle.standardError.write(Data("probe: \(backend.name) get failed\n".utf8))
        return 4
    }
    print(String(format: "%.4f", value))
    return 0
}

func runSet(_ target: Double) -> Int32 {
    guard let id = builtinDisplayID() else {
        FileHandle.standardError.write(Data("probe: no builtin display found\n".utf8))
        return 2
    }
    guard let backend = loadBrightnessBackend(for: id) else {
        FileHandle.standardError.write(Data("probe: no working brightness backend\n".utf8))
        return 3
    }
    let clamped = max(0.0, min(1.0, target))
    guard backend.set(id, clamped) else {
        FileHandle.standardError.write(Data("probe: \(backend.name) set failed\n".utf8))
        return 4
    }
    let readback = backend.get(id).map { String(format: "%.4f", $0) } ?? "n/a"
    print(String(format: "set %.4f readback %@ via %@", clamped, readback, backend.name))
    return 0
}

func runID() -> Int32 {
    guard let id = builtinDisplayID() else {
        FileHandle.standardError.write(Data("probe: no builtin display found\n".utf8))
        return 2
    }
    let backend = loadBrightnessBackend(for: id)
    print("builtin CGDirectDisplayID=\(id) backend=\(backend?.name ?? "NONE")")
    return 0
}

// MARK: - 入口

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    FileHandle.standardError.write(Data("usage: brightness-probe.swift [get|set <0.0-1.0>|id]\n".utf8))
    exit(1)
}

switch cmd {
case "get":
    exit(runGet())
case "set":
    guard args.count >= 2, let v = Double(args[1]) else {
        FileHandle.standardError.write(Data("usage: brightness-probe.swift set <0.0-1.0>\n".utf8))
        exit(1)
    }
    exit(runSet(v))
case "id":
    exit(runID())
default:
    FileHandle.standardError.write(Data("usage: brightness-probe.swift [get|set <0.0-1.0>|id]\n".utf8))
    exit(1)
}
