import AppKit
import ServiceManagement

enum SwitcherStyle: String, CaseIterable, Identifiable {
    case thumbnails, icons, list
    var id: Self { self }
    var title: String {
        switch self {
        case .thumbnails: String(localized: "Thumbnails")
        case .icons: String(localized: "App Icons")
        case .list: String(localized: "List")
        }
    }
}

enum ThumbnailSize: String, CaseIterable, Identifiable {
    case small, medium, large, auto
    var id: Self { self }
    /// The largest scale cells may use; every size still shrinks to fit the screen.
    var maxScale: CGFloat {
        switch self {
        case .small: 0.8
        case .medium: 1
        case .large: 1.25
        case .auto: 1.6
        }
    }
    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        case .auto: String(localized: "Auto")
        }
    }
}

enum Theme: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: Self { self }
    var appearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }
    var title: String {
        switch self {
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        case .system: String(localized: "System")
        }
    }
}

enum ShowOn: String, CaseIterable, Identifiable {
    case mouse, active, main
    var id: Self { self }
    var title: String {
        switch self {
        case .mouse: String(localized: "Screen with the pointer")
        case .active: String(localized: "Screen with the active window")
        case .main: String(localized: "Main screen")
        }
    }
}

enum TitleStyle: String, CaseIterable, Identifiable {
    case window, app, appAndWindow
    var id: Self { self }
    var title: String {
        switch self {
        case .window: String(localized: "Window title")
        case .app: String(localized: "App name")
        case .appAndWindow: String(localized: "App and window title")
        }
    }
}

enum Truncation: String, CaseIterable, Identifiable {
    case start, middle, end
    var id: Self { self }
    var lineBreakMode: NSLineBreakMode {
        switch self {
        case .start: .byTruncatingHead
        case .middle: .byTruncatingMiddle
        case .end: .byTruncatingTail
        }
    }
    var title: String {
        switch self {
        case .start: String(localized: "Start")
        case .middle: String(localized: "Middle")
        case .end: String(localized: "End")
        }
    }
}

enum BrowserTabsMode: String, CaseIterable, Identifiable {
    case off, search, always
    var id: Self { self }
    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .search: String(localized: "When Searching")
        case .always: String(localized: "Always")
        }
    }
}

enum GestureFingers: String, CaseIterable, Identifiable {
    case off, three, four
    var id: Self { self }
    var count: Int? { self == .three ? 3 : self == .four ? 4 : nil }
    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .three: String(localized: "Three Fingers")
        case .four: String(localized: "Four Fingers")
        }
    }
}

/// Per-app rules.
struct AppException: Codable, Equatable, Identifiable {
    var bundleID: String
    /// Never show this app's windows.
    var hideWindows = true
    /// Let this app receive the shortcuts instead (remote desktops, virtual machines).
    var ignoreShortcuts = false
    var id: String { bundleID }

    init(bundleID: String, hideWindows: Bool = true, ignoreShortcuts: Bool = false) {
        self.bundleID = bundleID
        self.hideWindows = hideWindows
        self.ignoreShortcuts = ignoreShortcuts
    }

    /// Tolerates fields added or removed by other versions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        hideWindows = try c.decodeIfPresent(Bool.self, forKey: .hideWindows) ?? true
        ignoreShortcuts = try c.decodeIfPresent(Bool.self, forKey: .ignoreShortcuts) ?? false
    }

    /// Apps that usually want the shortcut for themselves. Added on first launch.
    static let defaults: [AppException] = [
        "com.apple.ScreenSharing", "com.microsoft.rdc.macos", "com.teamviewer.TeamViewer", "org.virtualbox.app.VirtualBoxVM",
        "com.parallels.desktop.console", "com.vmware.fusion", "com.utmapp.UTM", "com.citrix.XenAppViewer",
    ].map { AppException(bundleID: $0, hideWindows: false, ignoreShortcuts: true) }

    static var installedDefaults: [AppException] {
        defaults.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }
}

/// User preferences, stored in UserDefaults. Settings views bind to the same keys with @AppStorage.
enum Prefs {
    enum Key {
        static let shortcuts = "shortcuts"
        static let style = "style"
        static let size = "size"
        static let theme = "theme"
        static let showOn = "showOn"
        static let titleStyle = "titleStyle"
        static let truncation = "truncation"
        static let showBadges = "showBadges"
        static let keepOpen = "keepOpen"
        static let preview = "previewSelected"
        static let gesture = "gesture"
        static let browserTabs = "browserTabs"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let exceptions = "exceptions"
        static let autoUpdate = "autoUpdate"
        static let backgroundCapture = "backgroundCapture"
        static let commandLine = "commandLine"
        static let didSetUpLoginItem = "didSetUpLoginItem"
        static let onboarding = "onboarding"
        static let declinedMove = "declinedMove"
        static let languages = "AppleLanguages"
    }

    private static let defaults = UserDefaults.standard

    static func register() {
        defaults.register(defaults: [
            Key.style: SwitcherStyle.thumbnails.rawValue,
            Key.size: ThumbnailSize.auto.rawValue,
            Key.theme: Theme.system.rawValue,
            Key.showOn: ShowOn.mouse.rawValue,
            Key.titleStyle: TitleStyle.window.rawValue,
            Key.truncation: Truncation.end.rawValue,
            Key.showBadges: true,
            Key.keepOpen: false,
            Key.preview: false,
            Key.gesture: GestureFingers.off.rawValue,
            Key.browserTabs: BrowserTabsMode.search.rawValue,
            Key.showMenuBarIcon: true,
            Key.autoUpdate: true,
            Key.backgroundCapture: false,
            Key.commandLine: false,
        ])
        seedExceptions()
    }

    /// First launch: remote desktop and virtual machine apps that are installed keep the shortcuts for themselves.
    private static func seedExceptions() {
        if defaults.data(forKey: Key.exceptions) == nil { exceptions = AppException.installedDefaults }
    }

    static var shortcuts: [ShortcutConfig] {
        get {
            let saved = decodeEach(ShortcutConfig.self, Key.shortcuts) ?? []
            return saved.isEmpty ? ShortcutConfig.defaults : Array(saved.prefix(ShortcutConfig.maxCount))
        }
        set {
            encode(Array(newValue.prefix(ShortcutConfig.maxCount)), Key.shortcuts)
            NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
        }
    }

    static var exceptions: [AppException] {
        get { decodeEach(AppException.self, Key.exceptions) ?? [] }
        set { encode(newValue, Key.exceptions) }
    }

    static var style: SwitcherStyle { value(Key.style, .thumbnails) }
    static var size: ThumbnailSize { value(Key.size, .auto) }
    static var theme: Theme { value(Key.theme, .system) }
    static var showOn: ShowOn { value(Key.showOn, .mouse) }
    static var titleStyle: TitleStyle { value(Key.titleStyle, .window) }
    static var truncation: Truncation { value(Key.truncation, .end) }
    static var gesture: GestureFingers { value(Key.gesture, .off) }
    static var browserTabs: BrowserTabsMode { value(Key.browserTabs, .search) }
    static var showBadges: Bool { defaults.bool(forKey: Key.showBadges) }
    static var keepOpen: Bool { defaults.bool(forKey: Key.keepOpen) }
    static var preview: Bool { defaults.bool(forKey: Key.preview) }
    static var showMenuBarIcon: Bool { defaults.bool(forKey: Key.showMenuBarIcon) }
    static var autoUpdate: Bool { defaults.bool(forKey: Key.autoUpdate) }
    static var backgroundCapture: Bool { defaults.bool(forKey: Key.backgroundCapture) }
    static var commandLine: Bool { defaults.bool(forKey: Key.commandLine) }

    /// Whether a window passes the per-app rules (each shortcut adds its own filters on top).
    static func includes(_ window: WindowInfo) -> Bool {
        guard let bundleID = window.app.bundleIdentifier else { return true }
        return !hiddenApps.contains(bundleID)
    }

    private static var hiddenApps: Set<String> { Set(exceptions.filter(\.hideWindows).map(\.bundleID)) }
    static var shortcutIgnoringApps: Set<String> { Set(exceptions.filter(\.ignoreShortcuts).map(\.bundleID)) }

    /// The system ⌘Tab switcher is turned off only while one of our shortcuts uses ⌘Tab.
    static func applyNativeCommandTab() {
        Private.setNativeCommandTab(enabled: !shortcuts.contains { $0.isCommandTab })
    }

    // MARK: Language

    static let languages = ["en", "de", "fr", "es", "it", "pt-BR", "nl", "sv", "da", "nb", "fi", "pl", "cs", "tr", "ru",
                            "uk", "ja", "ko", "zh-Hans", "zh-Hant", "vi"]

    /// nil = follow the system.
    static var language: String? {
        get {
            let own = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            return (own?[Key.languages] as? [String])?.first
        }
        set {
            if let newValue { defaults.set([newValue], forKey: Key.languages) } else { defaults.removeObject(forKey: Key.languages) }
        }
    }

    // MARK: Export / import

    static func exportSettings(to url: URL) throws {
        let domain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
        try data.write(to: url)
    }

    /// Every setting an exported file may carry, with the type it must have.
    private static let importable: [String: Any.Type] = [
        Key.shortcuts: Data.self, Key.exceptions: Data.self, Key.style: String.self, Key.size: String.self, Key.theme: String.self,
        Key.showOn: String.self, Key.titleStyle: String.self, Key.truncation: String.self, Key.showBadges: Bool.self,
        Key.keepOpen: Bool.self, Key.preview: Bool.self, Key.gesture: String.self, Key.browserTabs: String.self,
        Key.showMenuBarIcon: Bool.self, Key.autoUpdate: Bool.self, Key.backgroundCapture: Bool.self, Key.commandLine: Bool.self,
    ]

    /// Applies only known settings of the right type; anything else in the file is ignored.
    static func importSettings(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count < 1_000_000,
              let domain = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }
        for (key, type) in importable {
            guard let value = domain[key] else { continue }
            let valid: Bool
            switch type {
            case is Data.Type: valid = value is Data
            case is Bool.Type: valid = value is Bool || value is NSNumber
            default: valid = value is String
            }
            if valid { defaults.set(value, forKey: key) }
        }
    }

    static func resetSettings() {
        defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        defaults.set(true, forKey: Key.didSetUpLoginItem)
    }

    // MARK: Helpers

    private static func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        T(rawValue: defaults.string(forKey: key) ?? "") ?? fallback
    }

    /// Decodes a list element by element, so one unreadable entry (e.g. from a newer version) doesn't lose the rest.
    private static func decodeEach<T: Decodable>(_ type: T.Type, _ key: String) -> [T]? {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        return items.compactMap { item in
            (try? JSONSerialization.data(withJSONObject: item)).flatMap { try? JSONDecoder().decode(type, from: $0) }
        }
    }

    private static func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

extension Notification.Name {
    static let shortcutsChanged = Notification.Name("GlideTab.shortcutsChanged")
}

enum LoginItem {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    }
}

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() { openSettings("Privacy_ScreenCapture") }
    }

    enum AutomationState { case allowed, denied, notAsked, notRunning }

    /// Automation permission for controlling `bundleID` (browser tabs).
    ///
    /// The system call behind this asks the target app over Apple Events, and on some macOS versions it never
    /// returns when that app doesn't answer. So it runs on its own thread with a time limit, and a browser
    /// that didn't answer isn't asked again for a minute. Callers may still prefer a background thread.
    static func automation(_ bundleID: String) -> AutomationState {
        automationLock.lock()
        let recentlyHung = unresponsiveUntil[bundleID].map { $0 > Date() } ?? false
        let alreadyAsking = automationInFlight.contains(bundleID)
        if !recentlyHung && !alreadyAsking { automationInFlight.insert(bundleID) }
        automationLock.unlock()
        if recentlyHung || alreadyAsking { return .notRunning }

        final class Box: @unchecked Sendable { var state = AutomationState.notRunning }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        automationQueue.async {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            if let desc = target.aeDesc {
                switch AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false) {
                case noErr: box.state = .allowed
                case OSStatus(procNotFound): box.state = .notRunning
                case OSStatus(errAEEventWouldRequireUserConsent): box.state = .notAsked
                default: box.state = .denied
                }
            }
            automationLock.lock()
            automationInFlight.remove(bundleID)
            automationLock.unlock()
            done.signal()
        }
        if done.wait(timeout: .now() + 1.5) == .timedOut {
            automationLock.lock()
            unresponsiveUntil[bundleID] = Date(timeIntervalSinceNow: 60)
            automationLock.unlock()
            return .notRunning
        }
        return box.state
    }

    private static let automationQueue = DispatchQueue(label: "GlideTab.automation", attributes: .concurrent)
    private static let automationLock = NSLock()
    private static var automationInFlight: Set<String> = []
    private static var unresponsiveUntil: [String: Date] = [:]

    static func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}
