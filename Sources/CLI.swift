import AppKit

/// Command line client and server. The same binary forwards each command to the running app over a local
/// Mach port, so commands run with the app's permissions.
enum CLI {
    static let commands: Set<String> = ["list", "focus", "close", "minimize", "show", "settings", "help", "--help", "-h", "version", "--version"]
    private static let portName = ((Bundle.main.bundleIdentifier ?? "GlideTab") + ".cli") as CFString
    private static var port: CFMessagePort?

    private static let usage = """
    Usage: glidetab <command>

      list [--json]       List windows in switcher order (id, app, title, state)
      focus <id>          Switch to a window
      close <id>          Close a window
      minimize <id>       Minimize a window
      show                Open the switcher (stays open until you choose)
      settings            Open GlideTab Settings
      version             Print the version
    """

    // MARK: Client

    /// Runs a command against the running app and returns the process exit code.
    static func run(_ arguments: [String]) -> Int32 {
        guard let command = arguments.first else { return 1 }
        if ["help", "--help", "-h"].contains(command) {
            print(usage)
            return 0
        }
        if ["version", "--version"].contains(command) {
            print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
            return 0
        }
        guard let remote = CFMessagePortCreateRemote(nil, portName) else {
            FileHandle.standardError.write(Data("GlideTab isn't running, or its command line tool is off (Settings → General).\n".utf8))
            return 1
        }
        let request = Data(arguments.joined(separator: "\u{1f}").utf8) as CFData
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(remote, 0, request, 2, 5, CFRunLoopMode.defaultMode.rawValue, &reply)
        guard status == kCFMessagePortSuccess, let data = reply?.takeRetainedValue() as Data? else {
            FileHandle.standardError.write(Data("GlideTab didn't respond (\(status)).\n".utf8))
            return 1
        }
        let text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("error: ") {
            FileHandle.standardError.write(Data((text + "\n").utf8))
            return 1
        }
        if !text.isEmpty { print(text) }
        return 0
    }

    // MARK: Server

    private static var source: CFRunLoopSource?

    /// The command line tool is opt-in: while it's on, any program running as you can list and focus windows.
    static func setEnabled(_ enabled: Bool) {
        if enabled { startServer() } else { stopServer() }
    }

    private static func startServer() {
        guard port == nil else { return }
        var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        let callback: CFMessagePortCallBack = { _, _, data, _ in
            guard let data, CFDataGetLength(data) <= 4096 else {
                return Unmanaged.passRetained(Data("error: request too large".utf8) as CFData)
            }
            let request = String(decoding: data as Data, as: UTF8.self)
            let reply = CLI.respond(to: request.components(separatedBy: "\u{1f}"))
            return Unmanaged.passRetained(Data(reply.utf8) as CFData)
        }
        guard let port = CFMessagePortCreateLocal(nil, portName, callback, &context, nil) else {
            // Another process owns the name (or a second copy of GlideTab is running).
            FileHandle.standardError.write(Data("GlideTab: couldn't start the command line service.\n".utf8))
            return
        }
        let source = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.port = port
        self.source = source
    }

    private static func stopServer() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMessagePortInvalidate(port) }
        port = nil
        source = nil
    }

    /// Handles one command inside the app (main thread).
    private static func respond(to arguments: [String]) -> String {
        let command = arguments.first ?? ""
        func window() -> WindowInfo? {
            guard arguments.count > 1, let id = UInt32(arguments[1]) else { return nil }
            return WindowManager.shared.currentWindows().first { $0.id == id }
        }
        switch command {
        case "list":
            let windows = WindowManager.shared.currentWindows()
            return arguments.contains("--json") ? json(windows) : table(windows)
        case "focus", "close", "minimize":
            guard let target = window() else { return "error: no window with that id (see `glidetab list`)" }
            switch command {
            case "focus": WindowManager.shared.focus(target)
            case "close": WindowManager.shared.close(target)
            default: WindowManager.shared.minimize(target)
            }
            return ""
        case "show":
            Switcher.shared.showPinned()
            return ""
        case "settings":
            (NSApp.delegate as? AppDelegate)?.showSettings()
            return ""
        default:
            return "error: unknown command \"\(command)\"\n\n\(usage)"
        }
    }

    /// Window titles come from other apps: strip control characters so they can't inject terminal escape codes.
    private static func printable(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
    }

    private static func table(_ windows: [WindowInfo]) -> String {
        windows.map { w in
            var state: [String] = []
            if w.isMinimized { state.append("minimized") }
            if w.app.isHidden { state.append("hidden") }
            if w.isOnOtherSpace { state.append("other-space") }
            return [String(w.id), printable(w.appName), printable(w.displayTitle), state.joined(separator: ",")].joined(separator: "\t")
        }.joined(separator: "\n")
    }

    private static func json(_ windows: [WindowInfo]) -> String {
        let objects: [[String: Any]] = windows.map { w in
            ["id": w.id, "app": w.appName, "bundleId": w.app.bundleIdentifier ?? "", "pid": w.pid, "title": w.displayTitle,
             "minimized": w.isMinimized, "hidden": w.app.isHidden, "otherSpace": w.isOnOtherSpace]
        }
        let data = (try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
