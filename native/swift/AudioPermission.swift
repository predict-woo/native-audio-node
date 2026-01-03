import Foundation
import AppKit

// MARK: - Permission Status

public enum AudioPermissionStatus: Int32 {
    case unknown = 0
    case denied = 1
    case authorized = 2
}

// MARK: - TCC SPI Types

private typealias TCCPreflightFunc = @convention(c) (CFString, CFDictionary?) -> Int
private typealias TCCRequestFunc = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

// MARK: - TCC Framework Access

private class TCCFramework {
    static let shared = TCCFramework()

    private let handle: UnsafeMutableRawPointer?
    private let preflightFunc: TCCPreflightFunc?
    private let requestFunc: TCCRequestFunc?

    private init() {
        handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY)

        if let handle = handle {
            if let preflightSym = dlsym(handle, "TCCAccessPreflight") {
                preflightFunc = unsafeBitCast(preflightSym, to: TCCPreflightFunc.self)
            } else {
                preflightFunc = nil
            }

            if let requestSym = dlsym(handle, "TCCAccessRequest") {
                requestFunc = unsafeBitCast(requestSym, to: TCCRequestFunc.self)
            } else {
                requestFunc = nil
            }
        } else {
            preflightFunc = nil
            requestFunc = nil
        }
    }

    deinit {
        if let handle = handle {
            dlclose(handle)
        }
    }

    var isAvailable: Bool {
        return preflightFunc != nil && requestFunc != nil
    }

    func checkStatus() -> AudioPermissionStatus {
        guard let preflight = preflightFunc else {
            return .unknown
        }

        let service = "kTCCServiceAudioCapture" as CFString
        let result = preflight(service, nil)

        switch result {
        case 0:
            return .authorized
        case 1:
            return .denied
        default:
            return .unknown
        }
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        guard let request = requestFunc else {
            completion(false)
            return
        }

        let service = "kTCCServiceAudioCapture" as CFString
        request(service, nil) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
}

// MARK: - C-Compatible API

@_cdecl("audiotee_permission_status")
public func audiotee_permission_status() -> Int32 {
    return TCCFramework.shared.checkStatus().rawValue
}

@_cdecl("audiotee_permission_request")
public func audiotee_permission_request(
    callback: @escaping @convention(c) (Bool, UnsafeMutableRawPointer?) -> Void,
    context: UnsafeMutableRawPointer?
) {
    TCCFramework.shared.requestAccess { granted in
        callback(granted, context)
    }
}

@_cdecl("audiotee_permission_available")
public func audiotee_permission_available() -> Bool {
    return TCCFramework.shared.isAvailable
}

@_cdecl("audiotee_open_system_settings")
public func audiotee_open_system_settings() -> Bool {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    return NSWorkspace.shared.open(url)
}
