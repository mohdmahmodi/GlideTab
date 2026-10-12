import AppKit
import Carbon

/// A tab in a browser window, as reported by the browser.
final class BrowserTab {
    enum Handle {
        /// AppleScript window id + 1-based tab index (+ Chromium's stable tab id). Ids are kept as text:
        /// Chrome reports them as text, Safari as numbers, and the scripts compare them as text.
        case script(windowID: String, index: Int, tabID: String?)
        /// Accessibility element of the tab button (Firefox and friends).
        case accessibility(AXUIElement)
    }

    let app: NSRunningApplication
    let title: String
    let url: String
    let handle: Handle
    /// The window it lives in, when we could match it (needed to focus the right window and Space).
    var window: WindowInfo?
    /// Chrome-style profile name, taken from the window title ("… - Google Chrome - Work").
    var profile: String?

    init(app: NSRunningApplication, title: String, url: String, handle: Handle) {
        self.app = app
        self.title = title
        self.url = url
        self.handle = handle
    }

    var host: String {
        guard let host = URL(string: url)?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A browser window as the browser describes it, before matching it to a real window.
struct BrowserWindow {
    var scriptID: String?
    var name: String
    var bounds: CGRect?
    var windowID: CGWindowID?
    var activeIndex: Int
    var tabs: [(title: String, url: String, tabID: String?, element: AXUIElement?)]
}

/// Lists and switches browser tabs. Safari and Chromium browsers via AppleScript (all windows, all
/// profiles, all Spaces); Firefox-family browsers via Accessibility (windows on the current Space).
///
/// Results are cached and refreshed in the background, so the switcher never waits on a browser.
final class BrowserTabs {
    enum Engine { case chromium, safari, accessibility }

    static let shared = BrowserTabs()

    static let supported: [String: Engine] = [
        "com.google.Chrome": .chromium, "com.google.Chrome.beta": .chromium, "com.google.Chrome.dev": .chromium,
        "com.google.Chrome.canary": .chromium, "org.chromium.Chromium": .chromium, "com.brave.Browser": .chromium,
        "com.brave.Browser.beta": .chromium, "com.brave.Browser.nightly": .chromium, "com.microsoft.edgemac": .chromium,
        "com.microsoft.edgemac.Beta": .chromium, "com.microsoft.edgemac.Dev": .chromium, "com.vivaldi.Vivaldi": .chromium,
        "com.apple.Safari": .safari, "com.apple.SafariTechnologyPreview": .safari,
        "org.mozilla.firefox": .accessibility, "org.mozilla.firefoxdeveloperedition": .accessibility,
        "org.mozilla.nightly": .accessibility, "app.zen-browser.zen": .accessibility,
        "io.gitlab.librewolf-community": .accessibility,
    ]

    /// Main thread only.
    private var windowsByPid: [pid_t: [BrowserWindow]] = [:]
    private let queue = DispatchQueue(label: "GlideTab.browsers", qos: .userInitiated)
    /// Compiled scripts per bundle id. `queue` only.
    private var scripts: [String: NSAppleScript] = [:]
    private var refreshing: Set<pid_t> = []
    private var lastRefresh: [pid_t: Date] = [:]
    /// Don't ask a browser again within this many seconds (opening the switcher repeatedly would otherwise
    /// keep the browser busy answering).
    private static let minimumInterval: TimeInterval = 3

    private static func engine(for app: NSRunningApplication) -> Engine? {
        app.bundleIdentifier.flatMap { supported[$0] }
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        // Tabs mostly change while you're in the browser, so refresh as you leave it.
        center.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard Prefs.browserTabs != .off,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  Self.mayReadInBackground(app) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard !app.isActive, !app.isTerminated else { return }
                self?.refresh([app], force: true)
            }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.windowsByPid[app.processIdentifier] = nil
            self?.lastRefresh[app.processIdentifier] = nil
        }
        if Prefs.browserTabs != .off { refresh(NSWorkspace.shared.runningApplications.filter(Self.mayReadInBackground)) }
    }

    /// Background reads never trigger a permission prompt: only browsers you've already allowed are read
    /// without you asking. The first prompt comes when you search or open the switcher.
    private static func mayReadInBackground(_ app: NSRunningApplication) -> Bool {
        switch engine(for: app) {
        case .chromium, .safari: return app.bundleIdentifier.map { Permissions.automation($0) == .allowed } ?? false
        case .accessibility: return Permissions.accessibility
        case nil: return false
        }
    }

    func refreshAll(force: Bool = false, completion: (() -> Void)? = nil) {
        refresh(NSWorkspace.shared.runningApplications, force: force, completion: completion)
    }

    /// Re-reads tabs of any supported browsers in `apps`. `completion` runs on main once all have answered.
    func refresh(_ apps: [NSRunningApplication], force: Bool = false, completion: (() -> Void)? = nil) {
        let now = Date()
        let browsers = apps.filter { app in
            Self.engine(for: app) != nil && !app.isTerminated && !refreshing.contains(app.processIdentifier)
                && (force || now.timeIntervalSince(lastRefresh[app.processIdentifier] ?? .distantPast) >= Self.minimumInterval)
        }
        guard !browsers.isEmpty else {
            completion?()
            return
        }
        browsers.forEach { refreshing.insert($0.processIdentifier) }
        let group = DispatchGroup()
        for app in browsers {
            group.enter()
            queue.async {
                let windows = self.read(app)
                DispatchQueue.main.async {
                    self.refreshing.remove(app.processIdentifier)
                    self.lastRefresh[app.processIdentifier] = Date()
                    if let windows { self.windowsByPid[app.processIdentifier] = windows }
                    group.leave()
                }
            }
        }
        if let completion { group.notify(queue: .main, execute: completion) }
    }

    /// Tabs that aren't the visible tab of their window (those are already shown as the window itself),
    /// for browser windows that are in `windows` (i.e. passed the switcher's filters).
    func backgroundTabs(in windows: [WindowInfo]) -> [BrowserTab] {
        var result: [BrowserTab] = []
        for (pid, browserWindows) in windowsByPid {
            let candidates = windows.filter { $0.pid == pid }
            guard let app = candidates.first?.app else { continue }
            for browserWindow in browserWindows {
                guard let window = Self.match(browserWindow, among: candidates) else { continue }
                let profile = Self.profile(fromTitle: window.title, appName: window.appName)
                for (offset, tab) in browserWindow.tabs.enumerated() where offset + 1 != browserWindow.activeIndex {
                    let handle: BrowserTab.Handle
                    if let element = tab.element {
                        handle = .accessibility(element)
                    } else if let scriptID = browserWindow.scriptID {
                        handle = .script(windowID: scriptID, index: offset + 1, tabID: tab.tabID)
                    } else { continue }
                    let item = BrowserTab(app: app, title: tab.title.isEmpty ? tab.url : tab.title, url: tab.url, handle: handle)
                    item.window = window
                    item.profile = profile
                    result.append(item)
                }
            }
        }
        return result
    }

    /// Selects the tab inside its window, then calls `completion` on main (to focus the window).
    func select(_ tab: BrowserTab, completion: @escaping () -> Void) {
        queue.async {
            switch tab.handle {
            case let .script(windowID, index, tabID):
                // Chromium tabs are re-found by their id; Safari has no tab ids, so by address.
                _ = self.call(tab.app, "selecttab", [.init(string: windowID), .init(int32: Int32(index)),
                                                    .init(string: tabID ?? tab.url), .init(boolean: tab.window == nil)])
            case let .accessibility(element):
                AXUIElementPerformAction(element, kAXPressAction as CFString)
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    func close(_ tab: BrowserTab) {
        queue.async {
            switch tab.handle {
            case let .script(windowID, index, tabID):
                _ = self.call(tab.app, "closetab", [.init(string: windowID), .init(int32: Int32(index)),
                                                   .init(string: tabID ?? tab.url)])
            case let .accessibility(element):
                let children = element.value(kAXChildrenAttribute) as? [AXUIElement] ?? []
                let buttons = children.filter { $0.string(kAXRoleAttribute) == kAXButtonRole }
                if let button = buttons.first(where: { $0.string(kAXSubroleAttribute) == kAXCloseButtonSubrole })
                    ?? buttons.last { // the close button is the tab's last button (mute comes before it)
                    AXUIElementPerformAction(button, kAXPressAction as CFString)
                }
            }
            DispatchQueue.main.async { self.refresh([tab.app], force: true) }
        }
    }

    // MARK: Matching

    /// Finds the real window a browser window corresponds to: by window id, else by frame, else by title.
    static func match(_ browserWindow: BrowserWindow, among windows: [WindowInfo]) -> WindowInfo? {
        if let id = browserWindow.windowID { return windows.first { $0.id == id } }
        let index = matchIndex(name: browserWindow.name, bounds: browserWindow.bounds,
                               candidates: windows.map { ($0.frame, $0.title) })
        return index.map { windows[$0] }
    }

    static func matchIndex(name: String, bounds: CGRect?, candidates: [(frame: CGRect, title: String)]) -> Int? {
        func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
        }
        let titled = candidates.indices.filter { !name.isEmpty && candidates[$0].title.hasPrefix(name) }
        if let bounds {
            let framed = candidates.indices.filter { sameFrame(candidates[$0].frame, bounds) }
            if framed.count == 1 { return framed[0] }
            if let both = framed.first(where: titled.contains) { return both }
        }
        return titled.count == 1 ? titled[0] : nil
    }

    /// "YouTube - Google Chrome - Work" → "Work"
    static func profile(fromTitle title: String, appName: String) -> String? {
        guard !appName.isEmpty, let range = title.range(of: " - \(appName) - ", options: .backwards) else { return nil }
        let profile = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return profile.isEmpty ? nil : profile
    }

    // MARK: Reading (on `queue`)

    private func read(_ app: NSRunningApplication) -> [BrowserWindow]? {
        switch Self.engine(for: app) {
        case .chromium: return call(app, "listtabs", []).map { Self.parseChromium(Self.value(of: $0)) }
        case .safari: return call(app, "listtabs", []).map { Self.parseSafari(Self.value(of: $0)) }
        case .accessibility: return Self.readAccessibility(app)
        case nil: return nil
        }
    }

    /// Chromium: {window ids, names, bounds, active tab indexes, tab titles, tab URLs, tab ids}
    static func parseChromium(_ value: Any) -> [BrowserWindow] {
        guard let parts = value as? [Any], parts.count == 7,
              let ids = parts[0] as? [Any], let names = parts[1] as? [Any], let bounds = parts[2] as? [Any],
              let active = parts[3] as? [Any], let titles = parts[4] as? [Any], let urls = parts[5] as? [Any],
              let tabIDs = parts[6] as? [Any] else { return [] }
        return ids.indices.compactMap { i in
            guard let id = identifier(ids[i]), i < names.count, i < titles.count, i < urls.count else { return nil }
            let windowTitles = titles[i] as? [Any] ?? []
            let windowURLs = urls[i] as? [Any] ?? []
            let windowTabIDs = (i < tabIDs.count ? tabIDs[i] as? [Any] : nil) ?? []
            let tabs = windowTitles.indices.map { t in
                (title: string(windowTitles[t]),
                 url: t < windowURLs.count ? string(windowURLs[t]) : "",
                 tabID: t < windowTabIDs.count ? identifier(windowTabIDs[t]) : nil,
                 element: nil as AXUIElement?)
            }
            return BrowserWindow(scriptID: id, name: string(names[i]), bounds: i < bounds.count ? rect(bounds[i]) : nil,
                                 windowID: nil, activeIndex: i < active.count ? int(active[i]) ?? 1 : 1, tabs: tabs)
        }
    }

    /// Safari: {window ids, names, bounds, tab names, tab URLs, tab visible flags}
    static func parseSafari(_ value: Any) -> [BrowserWindow] {
        guard let parts = value as? [Any], parts.count == 6,
              let ids = parts[0] as? [Any], let names = parts[1] as? [Any], let bounds = parts[2] as? [Any],
              let titles = parts[3] as? [Any], let urls = parts[4] as? [Any], let visible = parts[5] as? [Any] else { return [] }
        return ids.indices.compactMap { i in
            guard let id = identifier(ids[i]), i < names.count, i < titles.count else { return nil }
            let windowTitles = titles[i] as? [Any] ?? []
            guard !windowTitles.isEmpty else { return nil } // Settings and other tab-less windows
            let windowURLs = (i < urls.count ? urls[i] as? [Any] : nil) ?? []
            let windowVisible = (i < visible.count ? visible[i] as? [Any] : nil) ?? []
            let activeIndex = (windowVisible.firstIndex { ($0 as? Bool) == true } ?? 0) + 1
            let tabs = windowTitles.indices.map { t in
                (title: string(windowTitles[t]), url: t < windowURLs.count ? string(windowURLs[t]) : "",
                 tabID: nil as String?, element: nil as AXUIElement?)
            }
            return BrowserWindow(scriptID: id, name: string(names[i]), bounds: i < bounds.count ? rect(bounds[i]) : nil,
                                 windowID: nil, activeIndex: activeIndex, tabs: tabs)
        }
    }

    private static func readAccessibility(_ app: NSRunningApplication) -> [BrowserWindow] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        let windows = element.value(kAXWindowsAttribute) as? [AXUIElement] ?? []
        windows.forEach { AXUIElementSetMessagingTimeout($0, 0.25) }
        return windows.compactMap { window in
            guard let id = window.windowID, let tabGroup = findTabGroup(in: window) else { return nil }
            let buttons = (tabGroup.value(kAXTabsAttribute) as? [AXUIElement])
                ?? (tabGroup.value(kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { $0.string(kAXRoleAttribute) == kAXRadioButtonRole }
            guard !buttons.isEmpty else { return nil }
            let activeIndex = (buttons.firstIndex { ($0.value(kAXValueAttribute) as? Int) == 1 } ?? 0) + 1
            let tabs = buttons.map { button in
                (title: button.string(kAXTitleAttribute) ?? button.string(kAXDescriptionAttribute) ?? "",
                 url: "", tabID: nil as String?, element: Optional(button))
            }
            return BrowserWindow(scriptID: nil, name: window.string(kAXTitleAttribute) ?? "", bounds: nil,
                                 windowID: id, activeIndex: activeIndex, tabs: tabs)
        }
    }

    /// Breadth-first search for the tab strip, skipping page content and capped so a huge tree can't stall us.
    private static func findTabGroup(in root: AXUIElement) -> AXUIElement? {
        var queue = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 300 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let role = element.string(kAXRoleAttribute)
            if role == kAXTabGroupRole { return element }
            guard depth < 6, role != "AXWebArea", role != kAXScrollAreaRole else { continue }
            for child in element.value(kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                AXUIElementSetMessagingTimeout(child, 0.25)
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    // MARK: AppleScript (on `queue`)

    private func call(_ app: NSRunningApplication, _ handler: String, _ arguments: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor? {
        // Sending an Apple event to a browser that isn't running would launch it.
        guard !app.isTerminated, let bundleID = app.bundleIdentifier, let script = script(for: bundleID) else { return nil }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent),
                                           targetDescriptor: .currentProcess(), returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        event.setDescriptor(NSAppleEventDescriptor(string: handler), forKeyword: AEKeyword(keyASSubroutineName))
        let list = NSAppleEventDescriptor.list()
        for (i, argument) in arguments.enumerated() { list.insert(argument, at: i + 1) }
        event.setDescriptor(list, forKeyword: keyDirectObject)
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        #if DEBUG
        if let error { lastError = "\(handler): \(error[NSAppleScript.errorNumber] ?? "?") \(error[NSAppleScript.errorMessage] ?? "")" }
        #endif
        return result
    }

    #if DEBUG
    /// The most recent AppleScript failure. `queue` only.
    private(set) var lastError: String?

    /// The raw Apple event answer to `listtabs`, or the error.
    func rawTabList(_ app: NSRunningApplication) -> String {
        queue.sync { call(app, "listtabs", []).map { "\($0)" } ?? "nil (\(lastError ?? "no error"))" }
    }
    #endif

    private func script(for bundleID: String) -> NSAppleScript? {
        if let script = scripts[bundleID] { return script }
        let source: String
        switch Self.supported[bundleID] {
        case .chromium: source = Self.chromiumScript(bundleID)
        case .safari: source = Self.safariScript(bundleID)
        default: return nil
        }
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { return nil }
        scripts[bundleID] = script
        return script
    }

    // Every handler first checks the browser is still running: asking "is running" never launches an app, while
    // any other command to a browser that has just quit would start it again. Timeouts keep a busy browser
    // from holding up the queue.

    private static func chromiumScript(_ bundleID: String) -> String {
        """
        on listtabs()
            if application id "\(bundleID)" is not running then return {}
            tell application id "\(bundleID)"
                with timeout of 3 seconds
                    return {id of every window, name of every window, bounds of every window, ¬
                        active tab index of every window, title of every tab of every window, ¬
                        URL of every tab of every window, id of every tab of every window}
                end timeout
            end tell
        end listtabs

        on findwindow(windowId)
            tell application id "\(bundleID)"
                set ids to id of every window
                repeat with i from 1 to count of ids
                    if (item i of ids as text) is windowId then return window i
                end repeat
            end tell
            error "window not found" number -1728
        end findwindow

        on findtab(w, idx, tabId)
            tell application id "\(bundleID)"
                set ids to id of every tab of w
                if idx ≤ (count of ids) and (tabId is "" or (item idx of ids as text) is tabId) then return idx
                repeat with i from 1 to count of ids
                    if (item i of ids as text) is tabId then return i
                end repeat
            end tell
            return 0
        end findtab

        on selecttab(windowId, idx, tabId, raiseWindow)
            if application id "\(bundleID)" is not running then return
            tell application id "\(bundleID)"
                with timeout of 2 seconds
                    set w to my findwindow(windowId)
                    set i to my findtab(w, idx, tabId)
                    if i > 0 then set active tab index of w to i
                    if raiseWindow then set index of w to 1
                end timeout
            end tell
        end selecttab

        on closetab(windowId, idx, tabId)
            if application id "\(bundleID)" is not running then return
            tell application id "\(bundleID)"
                with timeout of 2 seconds
                    set w to my findwindow(windowId)
                    set i to my findtab(w, idx, tabId)
                    if i > 0 then close tab i of w
                end timeout
            end tell
        end closetab
        """
    }

    private static func safariScript(_ bundleID: String) -> String {
        """
        on listtabs()
            if application id "\(bundleID)" is not running then return {}
            tell application id "\(bundleID)"
                with timeout of 3 seconds
                    return {id of every window, name of every window, bounds of every window, ¬
                        name of every tab of every window, URL of every tab of every window, ¬
                        visible of every tab of every window}
                end timeout
            end tell
        end listtabs

        on findwindow(windowId)
            tell application id "\(bundleID)"
                set ids to id of every window
                repeat with i from 1 to count of ids
                    if (item i of ids as text) is windowId then return window i
                end repeat
            end tell
            error "window not found" number -1728
        end findwindow

        -- Safari tabs have no ids: check the expected address, and look for it if the tabs moved.
        on findtab(w, idx, tabURL)
            tell application id "\(bundleID)"
                set urls to URL of every tab of w
                repeat with i from 1 to count of urls
                    set u to item i of urls
                    if u is missing value then set item i of urls to ""
                end repeat
                if idx ≤ (count of urls) and (tabURL is "" or (item idx of urls as text) is tabURL) then return idx
                repeat with i from 1 to count of urls
                    if (item i of urls as text) is tabURL then return i
                end repeat
            end tell
            return 0
        end findtab

        on selecttab(windowId, idx, tabURL, raiseWindow)
            if application id "\(bundleID)" is not running then return
            tell application id "\(bundleID)"
                with timeout of 2 seconds
                    set w to my findwindow(windowId)
                    set i to my findtab(w, idx, tabURL)
                    if i > 0 then set current tab of w to tab i of w
                    if raiseWindow then set index of w to 1
                end timeout
            end tell
        end selecttab

        on closetab(windowId, idx, tabURL)
            if application id "\(bundleID)" is not running then return
            tell application id "\(bundleID)"
                with timeout of 2 seconds
                    set w to my findwindow(windowId)
                    set i to my findtab(w, idx, tabURL)
                    if i > 0 then close tab i of w
                end timeout
            end tell
        end closetab
        """
    }

    // MARK: Apple event descriptor decoding

    static func value(of descriptor: NSAppleEventDescriptor) -> Any {
        switch descriptor.descriptorType {
        case typeAEList:
            guard descriptor.numberOfItems > 0 else { return [Any]() }
            return (1...descriptor.numberOfItems).map { value(of: descriptor.atIndex($0) ?? .null()) }
        case typeTrue: return true
        case typeFalse: return false
        case typeBoolean: return descriptor.booleanValue
        case typeSInt16, typeSInt32, typeSInt64, typeUInt16, typeUInt32, typeUInt64, typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint:
            return descriptor.doubleValue
        case typeNull, typeType: return NSNull() // includes `missing value`
        default: return descriptor.stringValue ?? NSNull()
        }
    }

    private static func string(_ value: Any) -> String { value as? String ?? "" }

    /// An id as text, whether the browser sent a number or a string.
    private static func identifier(_ value: Any) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        return int(value).map(String.init)
    }

    private static func int(_ value: Any) -> Int? {
        if let double = value as? Double { return Int(exactly: double.rounded()) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func rect(_ value: Any) -> CGRect? {
        guard let edges = (value as? [Any])?.compactMap({ $0 as? Double }), edges.count == 4 else { return nil }
        return CGRect(x: edges[0], y: edges[1], width: edges[2] - edges[0], height: edges[3] - edges[1])
    }
}
