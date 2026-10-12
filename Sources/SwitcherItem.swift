import AppKit

/// One entry in the switcher: a window, or a background browser tab.
enum SwitcherItem {
    case window(WindowInfo)
    case tab(BrowserTab)

    var app: NSRunningApplication {
        switch self {
        case let .window(window): window.app
        case let .tab(tab): tab.app
        }
    }

    var title: String {
        switch self {
        case let .window(window): window.displayTitle
        case let .tab(tab): tab.title
        }
    }

    /// Stable identity across updates within a session, so the UI can reuse views.
    var identity: ObjectIdentifier {
        switch self {
        case let .window(window): ObjectIdentifier(window)
        case let .tab(tab): ObjectIdentifier(tab)
        }
    }

    /// The title as the user chose to show it.
    func title(_ style: TitleStyle) -> String {
        guard case let .window(window) = self else { return title }
        let hasOwnTitle = !window.title.isEmpty && window.title != window.appName
        switch style {
        case .window: return window.displayTitle
        case .app: return window.appName
        case .appAndWindow: return hasOwnTitle ? "\(window.appName) – \(window.title)" : window.appName
        }
    }

    /// Secondary text, never repeating the title: for windows, whichever of app name and window title
    /// the title doesn't show; for tabs, "Profile · host".
    func subtitle(_ style: TitleStyle = .window) -> String {
        switch self {
        case let .window(window):
            guard !window.title.isEmpty, window.title != window.appName else { return "" }
            switch style {
            case .window: return window.appName
            case .app: return window.title
            case .appAndWindow: return ""
            }
        case let .tab(tab):
            return [tab.profile, tab.host.isEmpty ? nil : tab.host].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// The window shown for this item: itself, or the window holding the tab.
    var window: WindowInfo? {
        switch self {
        case let .window(window): window
        case let .tab(tab): tab.window
        }
    }

    /// Only windows have their own picture; a background tab isn't visible anywhere to capture.
    var thumbnailID: CGWindowID? {
        if case let .window(window) = self { return window.id }
        return nil
    }

    var isTab: Bool {
        if case .tab = self { return true }
        return false
    }

    var isMinimized: Bool { if case let .window(window) = self { window.isMinimized } else { false } }
    var isOnOtherSpace: Bool { window?.isOnOtherSpace ?? false }

    var actions: [WindowAction] { isTab ? [.close] : WindowAction.allCases }

    func matches(_ query: String) -> Bool {
        switch self {
        case let .window(window): window.matches(query)
        case let .tab(tab): Search.matches(query, in: "\(tab.title) \(tab.host) \(tab.app.localizedName ?? "") \(tab.profile ?? "")")
        }
    }

    func isSame(as other: SwitcherItem) -> Bool {
        switch (self, other) {
        case let (.window(a), .window(b)): a === b
        case let (.tab(a), .tab(b)): a === b
        default: false
        }
    }

    var accessibilityLabel: String {
        var parts = [title]
        if !subtitle().isEmpty { parts.append(subtitle()) }
        if isTab { parts.append(String(localized: "Tab")) }
        if isMinimized { parts.append(String(localized: "Minimized")) }
        if app.isHidden { parts.append(String(localized: "App hidden")) }
        if isOnOtherSpace { parts.append(String(localized: "On another Space")) }
        return parts.joined(separator: ", ")
    }
}

/// The buttons on a switcher item, drawn like the window buttons they stand for.
enum WindowAction: CaseIterable {
    case close, minimize, fullScreen

    var title: String {
        switch self {
        case .close: String(localized: "Close")
        case .minimize: String(localized: "Minimize")
        case .fullScreen: String(localized: "Full Screen")
        }
    }

    var symbol: String {
        switch self {
        case .close: "xmark"
        case .minimize: "minus"
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        }
    }

    var colors: (fill: NSColor, rim: NSColor) {
        let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat) in NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        switch self {
        case .close: return (rgb(1, 0.373, 0.341), rgb(0.886, 0.275, 0.247))
        case .minimize: return (rgb(0.996, 0.737, 0.180), rgb(0.882, 0.635, 0.157))
        case .fullScreen: return (rgb(0.157, 0.784, 0.251), rgb(0.106, 0.675, 0.180))
        }
    }
}
