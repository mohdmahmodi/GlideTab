import AppKit
import SwiftUI

/// The Settings window: native toolbar tabs across the top, one fixed-size page per tab, so switching tabs is
/// instant and never resizes or animates the window.
enum SettingsWindow {
    static func make() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []
        tabs.canPropagateSelectedChildViewControllerTitle = true
        tabs.addTabViewItem(item(String(localized: "General"), "gearshape", GeneralSettings()))
        tabs.addTabViewItem(item(String(localized: "Appearance"), "paintpalette", AppearanceSettings()))
        tabs.addTabViewItem(item(String(localized: "Shortcuts"), "command", ShortcutsSettings()))
        tabs.addTabViewItem(item(String(localized: "Browsers"), "safari", BrowserSettings()))
        tabs.addTabViewItem(item(String(localized: "Exceptions"), "hand.raised", ExceptionSettings()))
        tabs.addTabViewItem(item(String(localized: "Help"), "questionmark.circle", HelpSettings()))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setContentSize(SettingsMetrics.size)
        window.center()
        return window
    }

    private static func item<Content: View>(_ label: String, _ symbol: String, _ view: Content) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        controller.preferredContentSize = SettingsMetrics.size
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
