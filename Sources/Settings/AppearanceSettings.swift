import AppKit
import SwiftUI

struct AppearanceSettings: View {
    @AppStorage(Prefs.Key.style) private var style = SwitcherStyle.thumbnails
    @AppStorage(Prefs.Key.size) private var size = ThumbnailSize.auto
    @AppStorage(Prefs.Key.theme) private var theme = Theme.system
    @AppStorage(Prefs.Key.showOn) private var showOn = ShowOn.mouse
    @AppStorage(Prefs.Key.preview) private var preview = false
    @AppStorage(Prefs.Key.titleStyle) private var titleStyle = TitleStyle.window
    @AppStorage(Prefs.Key.truncation) private var truncation = Truncation.end
    @AppStorage(Prefs.Key.showBadges) private var showBadges = true
    @AppStorage(Prefs.Key.backgroundCapture) private var backgroundCapture = false

    var body: some View {
        SettingsPage {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Style").font(.system(size: 13, weight: .semibold))
                    Text("How windows are shown in the switcher.").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.leading, 4)
                HStack(spacing: 14) {
                    ForEach(SwitcherStyle.allCases) { option in
                        StyleCard(style: option, isSelected: style == option) {
                            withAnimation(.snappy(duration: 0.2)) { style = option }
                        }
                    }
                }
            }

            Card {
                SettingRow(title: "Size", detail: style == .list ? "Lists always use one size." : "Auto grows previews when only a few windows are open.",
                           icon: "arrow.up.left.and.arrow.down.right") {
                    SegmentedChoice(selection: $size, options: [
                        .init(value: .small, title: ThumbnailSize.small.title),
                        .init(value: .medium, title: ThumbnailSize.medium.title),
                        .init(value: .large, title: ThumbnailSize.large.title),
                        .init(value: .auto, title: ThumbnailSize.auto.title, symbol: "sparkles"),
                    ])
                    .frame(width: 300)
                    .disabled(style == .list)
                    .opacity(style == .list ? 0.5 : 1)
                }
                RowDivider()
                SettingRow(title: "Theme", icon: "circle.lefthalf.filled") {
                    SegmentedChoice(selection: $theme, options: [
                        .init(value: .light, title: Theme.light.title, symbol: "sun.max"),
                        .init(value: .dark, title: Theme.dark.title, symbol: "moon"),
                        .init(value: .system, title: Theme.system.title, symbol: "laptopcomputer"),
                    ])
                    .frame(width: 300)
                }
                RowDivider()
                SettingRow(title: "Show on", icon: "display") {
                    MenuPicker(label: "Show on", selection: $showOn, options: ShowOn.allCases, title: \.title)
                }
                RowDivider()
                SettingRow(title: "Preview the selected window", detail: "Shows it full size, in place, while you choose.", icon: "eye") {
                    Toggle("Preview the selected window", isOn: $preview).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                SettingRow(title: "Refresh thumbnails in the background",
                           detail: "Keeps thumbnails of windows you've left up to date. Can briefly flicker protected video, like streaming sites.",
                           icon: "arrow.clockwise") {
                    Toggle("Refresh thumbnails in the background", isOn: $backgroundCapture).labelsHidden().toggleStyle(.switch)
                }
            }

            CardSection(title: "Titles & Badges") {
                SettingRow(title: "Show", icon: "textformat") {
                    MenuPicker(label: "Show", selection: $titleStyle, options: TitleStyle.allCases, title: \.title)
                }
                RowDivider()
                SettingRow(title: "Shorten long titles at the", icon: "text.line.last.and.arrowtriangle.forward") {
                    SegmentedChoice(selection: $truncation, options: Truncation.allCases.map { .init(value: $0, title: $0.title) })
                        .frame(width: 220)
                }
                RowDivider()
                SettingRow(title: "Status badges", detail: "Marks minimized windows, hidden apps, other Spaces and browser tabs.", icon: "tag") {
                    Toggle("Status badges", isOn: $showBadges).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .onChange(of: style) { _, new in
            if new == .thumbnails, !Permissions.screenRecording { Permissions.requestScreenRecording() }
        }
    }
}

/// A preview of a switcher style over the user's own wallpaper.
private struct StyleCard: View {
    let style: SwitcherStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    WallpaperBackdrop()
                    mockup
                }
                .frame(height: 124)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 3 : 0.5)
                )
                .shadow(color: .black.opacity(isSelected ? 0.18 : 0.08), radius: isSelected ? 6 : 3, y: 2)
                Text(style.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var mockup: some View {
        switch style {
        case .thumbnails:
            MiniPanel {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in MiniWindow(icon: AppIcon.samples[i], selected: i == 1, scale: 0.85) }
                }
            }
        case .icons:
            MiniPanel {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(nsImage: AppIcon.samples[i]).resizable().frame(width: 34, height: 34)
                            .padding(4)
                            .background {
                                if i == 1 { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5) }
                            }
                    }
                }
            }
        case .list:
            MiniPanel {
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 5) {
                            Image(nsImage: AppIcon.samples[i]).resizable().frame(width: 12, height: 12)
                            Capsule()
                                .fill(i == 1 ? Color.white.opacity(0.9) : Color.primary.opacity(0.45))
                                .frame(width: CGFloat(54 - i * 8), height: 3.5)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 5)
                        .frame(width: 104, height: 17)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(i == 1 ? Color.accentColor : Color.clear))
                    }
                }
            }
        }
    }
}
