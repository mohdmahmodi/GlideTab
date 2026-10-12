import AppKit

/// Private macOS APIs. They're resolved at runtime with dlsym so that if Apple ever removes one,
/// the app degrades (falls back to public APIs) instead of failing to launch.
enum Private {
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func load<T>(_ names: String...) -> T? {
        for name in names {
            if let p = dlsym(skyLight, name) ?? dlsym(rtldDefault, name) {
                return unsafeBitCast(p, to: T.self)
            }
        }
        return nil
    }

    // Accessibility element -> CGWindowID
    static let axGetWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? =
        load("_AXUIElementGetWindow")
    // Builds an AX element from a raw token; the only way to reach windows on other Spaces
    static let axCreateWithRemoteToken: (@convention(c) (CFData) -> Unmanaged<AXUIElement>?)? =
        load("_AXUIElementCreateWithRemoteToken")

    private static let mainConnection: (@convention(c) () -> Int32)? =
        load("SLSMainConnectionID", "CGSMainConnectionID")
    private static let copySpacesForWindows: (@convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?)? =
        load("SLSCopySpacesForWindows", "CGSCopySpacesForWindows")
    private static let setSymbolicHotKeyEnabled: (@convention(c) (Int32, Bool) -> Int32)? =
        load("SLSSetSymbolicHotKeyEnabled", "CGSSetSymbolicHotKeyEnabled")

    private static let getProcessForPID: (@convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus)? =
        load("GetProcessForPID")
    private static let setFrontProcessWithOptions: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> Int32)? =
        load("_SLPSSetFrontProcessWithOptions")
    private static let postEventRecordTo: (@convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32)? =
        load("SLPSPostEventRecordTo")

    private static let copyManagedDisplaySpaces: (@convention(c) (Int32) -> Unmanaged<CFArray>?)? =
        load("SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces")

    /// The Spaces a window is on (empty for phantom/helper windows). nil when the API is unavailable.
    static func spaces(for id: CGWindowID) -> Set<UInt64>? {
        guard let copySpaces = copySpacesForWindows, let connection = mainConnection?() else { return nil }
        let allSpaces: Int32 = 7
        guard let spaces = copySpaces(connection, allSpaces, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber]
        else { return [] }
        return Set(spaces.map(\.uint64Value))
    }

    /// The Space currently showing on each display. nil when the API is unavailable.
    static func visibleSpaces() -> Set<UInt64>? {
        guard let copy = copyManagedDisplaySpaces, let connection = mainConnection?(),
              let displays = copy(connection)?.takeRetainedValue() as? [[String: Any]] else { return nil }
        let ids = displays.compactMap { (($0["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value }
        return ids.isEmpty ? nil : Set(ids)
    }

    /// Brings one specific window to the front and makes it key, switching Spaces if needed.
    /// Returns false if the private APIs are unavailable, so the caller can fall back to plain app activation.
    static func makeFrontWindow(pid: pid_t, id: CGWindowID) -> Bool {
        guard let getPSN = getProcessForPID, let setFront = setFrontProcessWithOptions, let post = postEventRecordTo else { return false }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == noErr else { return false }
        let userGenerated: UInt32 = 0x200
        // A failure here (e.g. the window just closed) lets the caller fall back to public APIs.
        guard setFront(&psn, id, userGenerated) == 0 else { return false }

        // Synthetic mouse-down delivered to the window by id, which makes it the key window.
        // The click point is far outside any window so no content gets clicked.
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xf8
        bytes[0x08] = 0x01 // left mouse down
        bytes[0x3a] = 0x10
        var windowID = id
        var point = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &point) { bytes.replaceSubrange(0x20..<0x30, with: $0) }
        withUnsafeBytes(of: &windowID) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        _ = post(&psn, &bytes)
        return true
    }

    /// Enables/disables the system ⌘Tab switcher (so we can take over ⌘Tab).
    static func setNativeCommandTab(enabled: Bool) {
        guard let set = setSymbolicHotKeyEnabled else { return }
        _ = set(1, enabled) // ⌘Tab
        _ = set(2, enabled) // ⌘⇧Tab
    }
}
