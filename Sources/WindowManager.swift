import AppKit

final class WindowInfo {
    let id: CGWindowID
    let app: NSRunningApplication
    let title: String
    let ax: AXUIElement?
    var isMinimized: Bool
    let isOnOtherSpace: Bool
    /// In global screen coordinates with a top-left origin (like CGWindowList and AppleScript bounds).
    let frame: CGRect

    var pid: pid_t { app.processIdentifier }
    var appName: String { app.localizedName ?? "" }
    var displayTitle: String { title.isEmpty ? appName : title }

    init(id: CGWindowID, app: NSRunningApplication, title: String, ax: AXUIElement?, isMinimized: Bool,
         isOnOtherSpace: Bool, frame: CGRect = .zero) {
        self.id = id
        self.frame = frame
        self.app = app
        self.title = title
        self.ax = ax
        self.isMinimized = isMinimized
        self.isOnOtherSpace = isOnOtherSpace
    }

    /// True if every word of `query` appears in the title or app name.
    func matches(_ query: String) -> Bool {
        Search.matches(query, in: "\(displayTitle) \(appName)")
    }

    /// Whether the window's center is on `screen`.
    func isOn(_ screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first else { return true }
        // Convert to AppKit's bottom-left origin.
        let center = CGPoint(x: frame.midX, y: primary.frame.maxY - frame.midY)
        return screen.frame.contains(center)
    }
}

enum Search {
    /// Case- and diacritic-insensitive; every word of the query must appear somewhere.
    static func matches(_ query: String, in text: String) -> Bool {
        let words = query.split(separator: " ")
        guard !words.isEmpty else { return true }
        return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Every place a query word appears in `text`, for highlighting. Overlaps are merged.
    static func highlights(_ query: String, in text: String) -> [NSRange] {
        let string = text as NSString
        var ranges: [NSRange] = []
        for word in query.split(separator: " ") {
            var searchRange = NSRange(location: 0, length: string.length)
            while searchRange.length > 0 {
                let found = string.range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
                guard found.location != NSNotFound, found.length > 0 else { break }
                ranges.append(found)
                searchRange = NSRange(location: NSMaxRange(found), length: string.length - NSMaxRange(found))
            }
        }
        ranges.sort { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in ranges {
            if let last = merged.last, range.location <= NSMaxRange(last) {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

}

extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success ? value : nil
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }
    func bool(_ attribute: String) -> Bool { (value(attribute) as? Bool) ?? false }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow = Private.axGetWindow, getWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }
}

/// Finds switchable windows, keeps them in most-recently-used order, and focuses them.
final class WindowManager {
    static let shared = WindowManager()

    /// Window IDs, most recently used first. Main thread only.
    private var mru: [CGWindowID] = []
    /// When we last switched to a window ourselves. Until macOS has caught up, our history is the truth.
    private var lastFocusRequest = Date.distantPast

    /// Apps that recently didn't answer Accessibility in time: skipped (window server data only) for a while.
    private var slowApps: [pid_t: Date] = [:]
    private static let axTimeout: Float = 0.15
    private let axQueue = DispatchQueue(label: "GlideTab.ax", qos: .userInteractive)

    func start() {
        mru = currentWindows().map(\.id)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // Give the app a moment to update its focused window (e.g. when activated by clicking a window).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.noteFocusedWindow(of: app) }
        }
    }

    private func touch(_ id: CGWindowID) {
        mru.removeAll { $0 == id }
        mru.insert(id, at: 0)
    }

    private func noteFocusedWindow(of app: NSRunningApplication) {
        // Rapid ⌥Tab toggling: this notification can arrive after you've already switched on again. Only an app
        // that's still in front, activated by something other than us, may reorder the history.
        guard app.isActive, Date().timeIntervalSince(lastFocusRequest) > 0.6 else { return }
        let previous = mru.first
        guard let id = AXUIElementCreateApplication(app.processIdentifier).element(kAXFocusedWindowAttribute)?.windowID else { return }
        touch(id)
        // Optionally refresh the thumbnail of the window we just left, so it stays current on other Spaces.
        if Prefs.backgroundCapture, let previous, previous != id {
            Thumbnails.shared.capture(ids: [previous])
        }
    }

    /// All switchable windows, most recently used first. Main thread only.
    func currentWindows() -> [WindowInfo] {
        dispatchPrecondition(condition: .onQueue(.main))
        let me = ProcessInfo.processInfo.processIdentifier
        var apps: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != me {
            apps[app.processIdentifier] = app
        }

        // 1. Every normal-level window the window server knows about, on all Spaces, front-to-back.
        struct ServerWindow { let id: CGWindowID; let pid: pid_t; let frame: CGRect; let name: String; let onScreen: Bool }
        var serverWindows: [ServerWindow] = []
        let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for d in raw {
            guard (d[kCGWindowLayer as String] as? Int) == 0,
                  let id = (d[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, apps[pid] != nil,
                  let bounds = d[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 40, frame.height >= 40,
                  ((d[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0
            else { continue }
            serverWindows.append(ServerWindow(
                id: id, pid: pid, frame: frame,
                name: d[kCGWindowName as String] as? String ?? "",
                onScreen: (d[kCGWindowIsOnscreen as String] as? Bool) ?? false))
        }

        // 2. Ask each app (in parallel) for its real windows. Accessibility sees the current Space,
        //    including minimized windows and windows of hidden apps.
        struct AXWindow { let element: AXUIElement; let title: String; let minimized: Bool }
        let pids = Array(Set(serverWindows.map(\.pid)))
        var axWindows: [CGWindowID: AXWindow] = [:]
        var axRejected: Set<CGWindowID> = []
        var appsWithAXWindows: Set<pid_t> = []
        let lock = NSLock()
        let now = Date()
        slowApps = slowApps.filter { now.timeIntervalSince($0.value) < 10 }
        let skipped = Set(slowApps.keys)
        var slow: [pid_t] = []
        DispatchQueue.concurrentPerform(iterations: pids.count) { i in
            let pid = pids[i]
            guard !skipped.contains(pid) else { return }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, Self.axTimeout)
            let started = CACurrentMediaTime()
            defer {
                // Judge the app on its whole answer, not just the first call.
                if CACurrentMediaTime() - started >= Double(Self.axTimeout) * 2 {
                    lock.lock()
                    slow.append(pid)
                    lock.unlock()
                }
            }
            guard let list = app.value(kAXWindowsAttribute) as? [AXUIElement], !list.isEmpty else { return }
            list.forEach { AXUIElementSetMessagingTimeout($0, Self.axTimeout) }
            var found: [(CGWindowID, AXWindow)] = []
            var rejected: [CGWindowID] = []
            for element in list {
                guard let id = element.windowID else { continue }
                let subrole = element.string(kAXSubroleAttribute)
                let title = element.string(kAXTitleAttribute) ?? ""
                // Standard windows and dialogs, plus titled windows with no proper subrole (Steam, some Java and
                // Qt apps). Panels, palettes and popovers have their own subroles and are left out.
                let isWindow = subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
                    || ((subrole == nil || subrole == "AXUnknown") && !title.isEmpty)
                if isWindow {
                    found.append((id, AXWindow(element: element, title: title, minimized: element.bool(kAXMinimizedAttribute))))
                } else {
                    rejected.append(id)
                }
            }
            lock.lock()
            for (id, window) in found { axWindows[id] = window }
            axRejected.formUnion(rejected)
            appsWithAXWindows.insert(pid)
            lock.unlock()
        }

        for pid in slow { slowApps[pid] = now }

        // 3. Merge the two views. Without Space information, windows off screen can't be told apart from
        // phantom ones, so those are left out rather than guessed at.
        let visibleSpaces = Private.visibleSpaces()
        var result: [CGWindowID: WindowInfo] = [:]
        var stackingOrder: [CGWindowID] = []
        for w in serverWindows {
            guard let app = apps[w.pid], result[w.id] == nil else { continue }
            let title: String, element: AXUIElement?, minimized: Bool
            if let ax = axWindows[w.id] {
                (title, element, minimized) = (ax.title.isEmpty ? w.name : ax.title, ax.element, ax.minimized)
            } else if axRejected.contains(w.id) {
                continue // a panel, palette, popover, etc.
            } else if w.onScreen {
                // Visible but not listed by Accessibility: only trust it for apps that expose no AX windows at all.
                guard !appsWithAXWindows.contains(w.pid) else { continue }
                (title, element, minimized) = (w.name, nil, false)
            } else {
                // Off-screen and unknown to Accessibility: it's real only if it lives on a Space that isn't showing.
                // (Apps keep closed windows and popups ordered out on the current Space; those aren't real.)
                guard w.frame.width >= 100, w.frame.height >= 100, let visibleSpaces,
                      let spaces = Private.spaces(for: w.id), !spaces.isEmpty,
                      spaces.isDisjoint(with: visibleSpaces) else { continue }
                (title, element, minimized) = (w.name, nil, false)
            }
            // Off screen for another reason than minimizing or hiding: it's on another Space only if it's on a
            // Space that isn't showing (inactive native tabs and Stage Manager sets are on the current one).
            var otherSpace = false
            if !w.onScreen && !minimized && !app.isHidden, let visibleSpaces, let spaces = Private.spaces(for: w.id) {
                otherSpace = !spaces.isEmpty && spaces.isDisjoint(with: visibleSpaces)
            }
            result[w.id] = WindowInfo(id: w.id, app: app, title: title, ax: element, isMinimized: minimized,
                                      isOnOtherSpace: otherSpace, frame: w.frame)
            stackingOrder.append(w.id)
        }

        // If focus changed without us (a click, Mission Control, the Dock), put the really focused window first.
        if Date().timeIntervalSince(lastFocusRequest) > 0.6, let front = NSWorkspace.shared.frontmostApplication,
           slowApps[front.processIdentifier] == nil {
            let element = AXUIElementCreateApplication(front.processIdentifier)
            AXUIElementSetMessagingTimeout(element, Self.axTimeout)
            if let focused = element.element(kAXFocusedWindowAttribute)?.windowID, result[focused] != nil, focused != mru.first {
                touch(focused)
            }
        }
        mru = Self.order(history: mru, stacking: stackingOrder)
        Thumbnails.shared.prune(keeping: Set(mru))
        return mru.compactMap { result[$0] }
    }

    /// Most-recently-used order. Our focus history wins, since it updates instantly while the window server's
    /// stacking order lags. Windows not seen yet follow in stacking order; closed ones drop out.
    static func order(history: [CGWindowID], stacking: [CGWindowID]) -> [CGWindowID] {
        let alive = Set(stacking)
        var seen = Set<CGWindowID>()
        let known = history.filter { alive.contains($0) && seen.insert($0).inserted }
        return known + stacking.filter { seen.insert($0).inserted }
    }

    /// Brings `window` to the front. `completion` runs on main once it's there.
    func focus(_ window: WindowInfo, fullScreen: Bool = false, completion: (() -> Void)? = nil) {
        touch(window.id)
        lastFocusRequest = Date()
        axQueue.async {
            if window.app.isHidden { window.app.unhide() }
            // Windows on other Spaces have no Accessibility element yet. The window server can bring them forward
            // by id directly; the (slow) element search is only needed to unminimize.
            let element = window.ax ?? (window.isMinimized ? Self.findElement(pid: window.pid, id: window.id) : nil)
            if window.isMinimized, let element {
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            if !Private.makeFrontWindow(pid: window.pid, id: window.id) {
                // Fallback without the private calls: make the app frontmost and its window main.
                let app = AXUIElementCreateApplication(window.pid)
                AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                if let element { AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue) }
                DispatchQueue.main.async { window.app.activate() }
            }
            if let element {
                AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                if fullScreen {
                    usleep(150_000) // let the window settle in front first
                    AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, kCFBooleanTrue)
                }
            }
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    func close(_ window: WindowInfo) {
        axQueue.async {
            guard let element = window.ax ?? Self.findElement(pid: window.pid, id: window.id),
                  let button = element.element(kAXCloseButtonAttribute) else { return }
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    func minimize(_ window: WindowInfo) {
        axQueue.async {
            guard let element = window.ax ?? Self.findElement(pid: window.pid, id: window.id) else { return }
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    /// Accessibility only lists windows on the current Space. For windows elsewhere, ask for elements by
    /// raw ID until one turns out to be the window we want. Time-boxed, since IDs are sparse.
    private static func findElement(pid: pid_t, id: CGWindowID) -> AXUIElement? {
        guard let create = Private.axCreateWithRemoteToken else { return nil }
        // The token is 20 bytes: process ID, 4 reserved bytes, the tag "coco", and a 64-bit element ID.
        var token = [UInt8](repeating: 0, count: 20)
        token.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
            raw.storeBytes(of: 0x636f_636f, toByteOffset: 8, as: UInt32.self)
        }
        let deadline = CACurrentMediaTime() + 0.3
        var elementID: UInt64 = 0
        while CACurrentMediaTime() < deadline {
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            elementID += 1
            if let element = create(Data(token) as CFData)?.takeRetainedValue(),
               element.windowID == id, element.string(kAXRoleAttribute) == kAXWindowRole {
                return element
            }
        }
        return nil
    }
}
