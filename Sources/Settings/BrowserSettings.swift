import AppKit
import Combine
import SwiftUI

struct BrowserSettings: View {
    @AppStorage(Prefs.Key.browserTabs) private var mode = BrowserTabsMode.search
    @State private var states: [String: Permissions.AutomationState] = [:]
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    /// Supported browsers that are installed: the common ones first, then the rest by name.
    private var installed: [String] {
        let common = ["com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
                      "com.vivaldi.Vivaldi", "org.chromium.Chromium", "org.mozilla.firefox", "app.zen-browser.zen"]
        let others = BrowserTabs.supported.keys.filter { !common.contains($0) }.sorted { AppIcon.name($0) < AppIcon.name($1) }
        return (common + others).filter(AppIcon.isInstalled)
    }

    var body: some View {
        SettingsPage {
            TabSearchPreview()

            Card {
                SettingRow(title: "Show browser tabs", detail: modeDescription, icon: "globe") {
                    SegmentedChoice(selection: $mode, options: [
                        .init(value: .off, title: BrowserTabsMode.off.title),
                        .init(value: .search, title: BrowserTabsMode.search.title, symbol: "magnifyingglass"),
                        .init(value: .always, title: BrowserTabsMode.always.title),
                    ])
                    .frame(width: 430)
                }
            }

            CardSection(title: "Browsers", subtitle: "Every window and every profile. macOS asks once per browser before GlideTab can read its tabs.") {
                if installed.isEmpty {
                    Text("No supported browsers found.").foregroundStyle(.secondary).padding(16)
                }
                ForEach(Array(installed.enumerated()), id: \.element) { index, bundleID in
                    if index > 0 { RowDivider() }
                    browserRow(bundleID)
                }
            }
        }
        .onAppear(perform: update)
        .onReceive(refresh) { _ in update() }
        .onChange(of: mode) { _, new in if new != .off { BrowserTabs.shared.refreshAll(force: true) } }
    }

    private var modeDescription: LocalizedStringKey {
        switch mode {
        case .off: "Only windows appear in the switcher."
        case .search: "Background tabs appear when you type a search."
        case .always: "Background tabs always appear, after your windows."
        }
    }

    @ViewBuilder private func browserRow(_ bundleID: String) -> some View {
        let usesAccessibility = BrowserTabs.supported[bundleID] == .accessibility
        HStack(spacing: 12) {
            Image(nsImage: AppIcon.of(bundleID)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppIcon.name(bundleID))
                Text(usesAccessibility ? "Tabs in windows on the current Space" : "Tabs in every window, on every Space")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if usesAccessibility {
                StatusPill(text: Permissions.accessibility ? "Ready" : "Needs Accessibility", good: Permissions.accessibility)
            } else {
                switch states[bundleID] ?? .notRunning {
                case .allowed: StatusPill(text: "Allowed")
                case .notAsked: StatusPill(text: "Asks on first use", good: false)
                case .notRunning: StatusPill(text: "Not running", good: false)
                case .denied: Button("Allow…") { Permissions.openSettings("Privacy_Automation") }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func update() {
        var next: [String: Permissions.AutomationState] = [:]
        for bundleID in installed where BrowserTabs.supported[bundleID] != .accessibility {
            next[bundleID] = Permissions.automation(bundleID)
        }
        states = next
    }
}

/// A miniature switcher searching browser tabs, over the user's wallpaper.
private struct TabSearchPreview: View {
    var body: some View {
        ZStack {
            WallpaperBackdrop()
            MiniPanel {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        Text("docs").font(.system(size: 13))
                        Rectangle().fill(Color.accentColor).frame(width: 1.5, height: 14)
                        Spacer()
                        Text("2 of 14").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.primary.opacity(0.06)))
                    SampleTabRow(bundleID: "com.google.Chrome", title: "Q3 Planning – Google Docs", detail: "Work · docs.google.com",
                                 selected: true)
                    SampleTabRow(bundleID: "com.apple.Safari", title: "Swift Documentation", detail: "developer.apple.com")
                }
                .frame(width: 330)
            }
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
