import AppKit
import SwiftUI

// Shared building blocks for the Settings window.

enum SettingsMetrics {
    /// A fixed landscape window; longer pages scroll. Shorter on small displays, leaving room for the toolbar.
    static let width: CGFloat = 860
    static let height = min(600, (NSScreen.main?.visibleFrame.height ?? 900) - 110)
    static var size: CGSize { CGSize(width: width, height: height) }
}

/// A page with consistent padding.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 24)
                .frame(width: SettingsMetrics.width, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .frame(width: SettingsMetrics.width, height: SettingsMetrics.height)
    }
}

/// Title and one-line explanation at the top of a page, with an optional control on the right.
struct PageHeader<Accessory: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            accessory
        }
        .padding(.leading, 4)
    }
}

extension PageHeader where Accessory == EmptyView {
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A titled group of rows on a rounded card.
struct CardSection<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            }
            .padding(.leading, 4)
            Card { content }
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .cardBackground()
    }
}

extension View {
    func cardBackground(radius: CGFloat = 12) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.quaternary.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
    }
}

/// Label (with optional icon and detail) on the left, control on the right.
struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    var icon: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            if let icon { IconTile(symbol: icon) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 46)
    }
}

struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 14) }
}

/// An SF Symbol on a small neutral tile, like System Settings rows.
struct IconTile: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary))
    }
}

/// A compact menu picker without a label.
struct MenuPicker<Value: Hashable & Identifiable>: View {
    let label: LocalizedStringKey
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options) { Text(title($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// Segmented control with icons and an accent-filled selection that slides between options.
struct SegmentedChoice<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        var symbol: String? = nil
    }

    @Binding var selection: Value
    let options: [Option]
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let isSelected = option.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option.value }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = option.symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                        Text(option.title).lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor)
                                .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
    }
}

struct StatusPill: View {
    let text: LocalizedStringKey
    var good = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: good ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(good ? Color.green : Color.secondary)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

/// Buttons under a list, like Finder's and System Settings' + / −.
struct AddRemoveBar: View {
    let canRemove: Bool
    let add: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) { Image(systemName: "plus").frame(width: 28, height: 22) }
                .help("Add")
            Divider().frame(height: 14)
            Button(action: remove) { Image(systemName: "minus").frame(width: 28, height: 22) }
                .disabled(!canRemove)
                .help("Remove")
        }
        .buttonStyle(.borderless)
        .padding(2)
        .cardBackground(radius: 7)
    }
}

/// A selectable row in a master list (shortcuts, exceptions).
struct MasterRow: View {
    let title: String
    let subtitle: String
    var icon: NSImage? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(subtitle).font(.system(size: 11.5)).lineLimit(1)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.6))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    static func of(_ bundleID: String) -> NSImage {
        if let icon = cache[bundleID] { return icon }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        cache[bundleID] = icon
        return icon
    }

    static func name(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { ($0.path as NSString).lastPathComponent }
            .map { FileManager.default.displayName(atPath: $0) }
            .map { ($0 as NSString).deletingPathExtension } ?? bundleID
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Icons for illustrations: apps every Mac has.
    static var samples: [NSImage] {
        ["com.apple.Safari", "com.apple.finder", "com.apple.Notes"].map(of)
    }
}

/// A browser tab as the switcher lists it, for illustrations.
struct SampleTabRow: View {
    let bundleID: String
    let title: String
    let detail: String
    var selected = false
    var scale: CGFloat = 1

    var body: some View {
        let secondary = selected ? Color.white.opacity(0.85) : Color.secondary
        HStack(spacing: 7 * scale) {
            Image(nsImage: AppIcon.of(bundleID)).resizable().frame(width: 15 * scale, height: 15 * scale)
            Text(verbatim: title).font(.system(size: 11.5 * scale)).lineLimit(1)
            Spacer(minLength: 6 * scale)
            Text(verbatim: detail).font(.system(size: 10.5 * scale)).foregroundStyle(secondary).lineLimit(1)
            Image(systemName: "globe").font(.system(size: 9.5 * scale)).foregroundStyle(secondary)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 8 * scale)
        .frame(height: 24 * scale)
        .background(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous).fill(selected ? Color.accentColor : .clear))
    }
}

/// The user's own desktop picture, downsampled, as a backdrop for previews. Decoded off the main thread
/// (a large HEIC takes a while) and kept until the wallpaper changes.
enum Wallpaper {
    private(set) static var image: NSImage?
    private static var url: URL?

    static func load(_ completion: @escaping (NSImage?) -> Void) {
        guard let screen = NSScreen.main, let current = NSWorkspace.shared.desktopImageURL(for: screen) else { return completion(nil) }
        if current == url, let image { return completion(image) }
        DispatchQueue.global(qos: .userInitiated).async {
            var decoded: NSImage?
            if let source = CGImageSourceCreateWithURL(current as CFURL, nil),
               let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceThumbnailMaxPixelSize: 1000,
               ] as CFDictionary) {
                decoded = NSImage(cgImage: cgImage, size: .zero)
            }
            DispatchQueue.main.async {
                url = current
                image = decoded
                completion(decoded)
            }
        }
    }
}

struct WallpaperBackdrop: View {
    @State private var image = Wallpaper.image

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .onAppear { Wallpaper.load { image = $0 } }
    }
}

/// A miniature switcher panel for previews.
struct MiniPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

/// A miniature window thumbnail with its title row.
struct MiniWindow: View {
    let icon: NSImage
    var selected = false
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            HStack(spacing: 3 * scale) {
                Image(nsImage: icon).resizable().frame(width: 9 * scale, height: 9 * scale)
                Capsule().fill(.primary.opacity(0.45)).frame(width: 22 * scale, height: 3 * scale)
            }
            RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
                .fill(Color.white)
                .frame(width: 50 * scale, height: 34 * scale)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 3 * scale) {
                        WindowButtonDots(spacing: 2 * scale)
                        .frame(width: 14 * scale, height: 3.5 * scale)
                        ForEach(0..<3, id: \.self) { i in
                            Capsule().fill(Color.black.opacity(0.12)).frame(width: CGFloat(30 - i * 6) * scale, height: 2.5 * scale)
                        }
                    }
                    .padding(4 * scale)
                }
        }
        .padding(4 * scale)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 5 * scale, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
    }
}

/// The three window buttons as plain dots, for illustrations.
struct WindowButtonDots: View {
    var spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(WindowAction.allCases, id: \.self) { Circle().fill(Color(nsColor: $0.colors.fill)) }
        }
    }
}

// MARK: - Keyboard keys

/// A keycap drawn the way Apple prints them: modifier symbol in the corner and its name below. Dark in Dark Mode,
/// like a MacBook; white in Light Mode, like a Magic Keyboard.
struct MacKey: View {
    var topLeft: String? = nil
    var topRight: String? = nil
    var bottomLeft: String? = nil
    var bottomRight: String? = nil
    var centerTop: String? = nil
    var center: String? = nil
    /// Width in key units (1 = a letter key).
    var width: CGFloat = 1
    /// Half-height, like the ▲ ▼ keys.
    var short = false
    var scale: CGFloat = 1
    var highlighted = false

    private var unit: CGFloat { 42 * scale }

    var body: some View {
        let wordFont = Font.system(size: max(8, 9.5 * scale), weight: .regular)
        let symbolFont = Font.system(size: 12 * scale, weight: .regular)
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if let topLeft { Text(topLeft).font(symbolFont) }
                    Spacer(minLength: 0)
                    if let topRight { Text(topRight).font(symbolFont) }
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    if let bottomLeft { Text(bottomLeft).font(wordFont).lineLimit(1).fixedSize() }
                    Spacer(minLength: 0)
                    if let bottomRight { Text(bottomRight).font(wordFont).lineLimit(1).fixedSize() }
                }
            }
            .padding(.horizontal, 6 * scale)
            .padding(.vertical, 5 * scale)
            if centerTop != nil || center != nil {
                VStack(spacing: 1 * scale) {
                    if let centerTop { Text(centerTop).font(.system(size: 11 * scale)) }
                    if let center { Text(center).font(.system(size: (centerTop == nil ? 15 : 12) * scale, weight: .regular)) }
                }
            }
        }
        .foregroundStyle(.primary.opacity(0.88))
        .frame(width: unit * width + 5 * scale * (width - 1), height: short ? unit * 0.48 : unit)
        .background(
            RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1.2 * scale)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: highlighted ? 2 : 0.5)
        )
    }

    static func command(_ scale: CGFloat = 1) -> MacKey { MacKey(topRight: "⌘", bottomRight: "command", width: 1.6, scale: scale) }
    static func option(_ scale: CGFloat = 1) -> MacKey { MacKey(topRight: "⌥", bottomRight: "option", width: 1.35, scale: scale) }
    static func control(_ scale: CGFloat = 1) -> MacKey { MacKey(topRight: "⌃", bottomRight: "control", width: 1.4, scale: scale) }
    static func shift(_ scale: CGFloat = 1) -> MacKey { MacKey(topLeft: "⇧", bottomLeft: "shift", width: 1.6, scale: scale) }
    static func tab(_ scale: CGFloat = 1) -> MacKey { MacKey(topLeft: "⇥", bottomLeft: "tab", width: 1.45, scale: scale) }
    static func returnKey(_ scale: CGFloat = 1) -> MacKey { MacKey(topRight: "↩", bottomRight: "return", width: 1.6, scale: scale) }
    static func escape(_ scale: CGFloat = 1) -> MacKey { MacKey(bottomLeft: "esc", width: 1.2, scale: scale) }
    static func delete(_ scale: CGFloat = 1) -> MacKey { MacKey(bottomRight: "delete", width: 1.45, scale: scale) }

    /// The key for any key code, on the current keyboard layout.
    static func forKeyCode(_ keyCode: Int64, scale: CGFloat = 1) -> MacKey {
        switch keyCode {
        case KeyCode.tab: return .tab(scale)
        case KeyCode.returnKey: return .returnKey(scale)
        case KeyCode.enter: return MacKey(bottomRight: "enter", width: 1.3, scale: scale)
        case KeyCode.escape: return .escape(scale)
        case KeyCode.delete: return .delete(scale)
        case KeyCode.forwardDelete: return MacKey(topRight: "⌦", bottomRight: "delete", width: 1.2, scale: scale)
        case KeyCode.space: return MacKey(width: 3, scale: scale)
        case KeyCode.left: return MacKey(center: "◀", scale: scale)
        case KeyCode.right: return MacKey(center: "▶", scale: scale)
        case KeyCode.up: return MacKey(center: "▲", scale: scale)
        case KeyCode.down: return MacKey(center: "▼", scale: scale)
        default:
            if let chars = KeyNames.characters(for: keyCode) {
                if chars.normal.uppercased() == chars.shifted.uppercased() || chars.normal.first?.isLetter == true {
                    return MacKey(center: chars.normal.uppercased(), scale: scale)
                }
                return MacKey(centerTop: chars.shifted, center: chars.normal, scale: scale)
            }
            return MacKey(center: KeyNames.name(for: keyCode), width: 1.2, scale: scale)
        }
    }

    static func modifiers(_ flags: CGEventFlags, scale: CGFloat = 1) -> [MacKey] {
        var keys: [MacKey] = []
        if flags.contains(.maskControl) { keys.append(.control(scale)) }
        if flags.contains(.maskAlternate) { keys.append(.option(scale)) }
        if flags.contains(.maskShift) { keys.append(.shift(scale)) }
        if flags.contains(.maskCommand) { keys.append(.command(scale)) }
        return keys
    }
}

/// The inverted-T arrow keys, with half-height ▲ ▼ like on Mac keyboards.
struct ArrowKeys: View {
    var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .bottom, spacing: 5 * scale) {
            MacKey(center: "◀", short: true, scale: scale)
            VStack(spacing: 2 * scale) {
                MacKey(center: "▲", short: true, scale: scale)
                MacKey(center: "▼", short: true, scale: scale)
            }
            MacKey(center: "▶", short: true, scale: scale)
        }
    }
}

/// A shortcut as keys: [⌘ command] + [⇥ tab]
struct ShortcutKeys: View {
    let shortcut: ShortcutConfig
    var scale: CGFloat = 1
    var highlighted = false

    var body: some View {
        HStack(spacing: 7 * scale) {
            let modifiers = MacKey.modifiers(shortcut.flags, scale: scale)
            ForEach(modifiers.indices, id: \.self) { i in modifiers[i].highlightedIf(highlighted) }
            Text("+").font(.system(size: 14 * scale, weight: .medium)).foregroundStyle(.secondary)
            MacKey.forKeyCode(shortcut.keyCode, scale: scale).highlightedIf(highlighted)
        }
    }
}

extension MacKey {
    func highlightedIf(_ on: Bool) -> MacKey {
        var key = self
        key.highlighted = on
        return key
    }
}
