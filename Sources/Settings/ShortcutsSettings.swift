import AppKit
import Combine
import SwiftUI

struct ShortcutsSettings: View {
    @AppStorage(Prefs.Key.keepOpen) private var keepOpen = false
    @AppStorage(Prefs.Key.gesture) private var gesture = GestureFingers.off
    @State private var shortcuts = Prefs.shortcuts
    @State private var recording: UUID?
    @State private var accessibility = Permissions.accessibility
    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPage {
            PageHeader(title: "Shortcuts",
                       subtitle: "Hold the first key and press the second to open the switcher. Press the second key again to move. Let go to switch.") {
                Button {
                    add()
                } label: {
                    Label("Add Shortcut", systemImage: "plus")
                }
                .disabled(shortcuts.count >= ShortcutConfig.maxCount || nextFreeShortcut == nil)
            }

            VStack(spacing: 12) {
                ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    ShortcutCard(shortcut: binding(for: shortcut.id), number: index + 1, recording: $recording,
                                 canRemove: shortcuts.count > 1, accessibility: accessibility,
                                 setKeys: { setKeys($0, for: shortcut.id) }) {
                        if recording == shortcut.id {
                            recording = nil
                            Switcher.shared.cancelRecording()
                        }
                        shortcuts.removeAll { $0.id == shortcut.id }
                    }
                }
            }

            TrackpadCard(gesture: $gesture)

            CardSection(title: "While the switcher is open") {
                SwitcherKeysGuide(holdKeys: shortcuts.first.map { MacKey.modifiers($0.holdFlags, scale: 0.72) } ?? [], keepOpen: keepOpen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                RowDivider()
                SettingRow(title: "When you let go of the keys", icon: "hand.raised") {
                    SegmentedChoice(selection: $keepOpen, options: [
                        .init(value: false, title: String(localized: "Switch"), symbol: "arrow.right.circle"),
                        .init(value: true, title: String(localized: "Stay Open"), symbol: "pin"),
                    ])
                    .frame(width: 300)
                }
            }
        }
        .onChange(of: shortcuts) { _, new in Prefs.shortcuts = new }
        .onReceive(refresh) { _ in accessibility = Permissions.accessibility }
        .onDisappear {
            if recording != nil {
                recording = nil
                Switcher.shared.cancelRecording()
            }
        }
    }

    /// A combination no shortcut uses yet, as a starting point; the user then records the keys they want.
    private var nextFreeShortcut: ShortcutConfig? {
        let candidates: [CGEventFlags] = [.maskControl, [.maskControl, .maskAlternate], [.maskControl, .maskCommand], [.maskAlternate, .maskCommand]]
        for keyCode in [KeyCode.tab, KeyCode.grave] {
            for flags in candidates {
                let candidate = ShortcutConfig(keyCode: keyCode, modifiers: flags.rawValue)
                if !shortcuts.contains(where: { $0.sameKeys(as: candidate) }) { return candidate }
            }
        }
        return nil
    }

    private func add() {
        if let candidate = nextFreeShortcut { shortcuts.append(candidate) }
    }

    /// Bindings and updates go through the shortcut's id, never a position that can change underneath.
    private func binding(for id: UUID) -> Binding<ShortcutConfig> {
        Binding(get: { shortcuts.first { $0.id == id } ?? ShortcutConfig.defaults[0] },
                set: { new in if let i = shortcuts.firstIndex(where: { $0.id == id }) { shortcuts[i] = new } })
    }

    private func setKeys(_ recorded: ShortcutConfig, for id: UUID) {
        guard let i = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        guard !shortcuts.contains(where: { $0.id != id && $0.sameKeys(as: recorded) }) else { return NSSound.beep() }
        shortcuts[i].keyCode = recorded.keyCode
        shortcuts[i].modifiers = recorded.modifiers
    }
}

/// One shortcut: its keys (click to record new ones) and which windows it shows.
private struct ShortcutCard: View {
    @Binding var shortcut: ShortcutConfig
    let number: Int
    @Binding var recording: UUID?
    let canRemove: Bool
    let accessibility: Bool
    let setKeys: (ShortcutConfig) -> Void
    let remove: () -> Void

    private var isRecording: Bool { recording == shortcut.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Shortcut \(number)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    Button(action: toggleRecording) {
                        Group {
                            if isRecording {
                                HStack(spacing: 7) {
                                    MacKey(center: "…", width: 1.5, highlighted: true)
                                    Text("+").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                                    MacKey(center: "…", highlighted: true)
                                }
                            } else {
                                ShortcutKeys(shortcut: shortcut)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!accessibility)
                    .help("Click to record new keys")
                    .accessibilityLabel(Text("Shortcut: \(shortcut.displayString). Click to change."))
                    HStack(spacing: 12) {
                        Button(isRecording ? "Cancel" : "Change Keys…", action: toggleRecording)
                            .controlSize(.small)
                            .disabled(!accessibility)
                        if canRemove {
                            Button("Remove", action: remove)
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .foregroundStyle(.red)
                                .disabled(isRecording)
                        }
                    }
                }
                .frame(width: 230, alignment: .leading)

                SwiftUI.Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        FilterPicker(title: "Apps", selection: $shortcut.apps, options: ShortcutConfig.AppFilter.allCases, label: \.title)
                        FilterPicker(title: "Spaces", selection: $shortcut.spaces, options: ShortcutConfig.SpaceFilter.allCases, label: \.title)
                        FilterPicker(title: "Screens", selection: $shortcut.screens, options: ShortcutConfig.ScreenFilter.allCases, label: \.title)
                    }
                    GridRow {
                        FilterPicker(title: "Minimized windows", selection: $shortcut.minimized,
                                     options: ShortcutConfig.Visibility.allCases, label: \.title)
                        FilterPicker(title: "Hidden apps", selection: $shortcut.hidden, options: ShortcutConfig.Visibility.allCases, label: \.title)
                    }
                }
            }

            if isRecording || !accessibility {
                Text(isRecording ? "Press the new keys now, for example ⌥ option and tab. Use at least one of ⌘ command, ⌥ option or ⌃ control. Press esc to cancel."
                                 : "Changing keys needs the Accessibility permission (see General).")
                    .font(.callout)
                    .foregroundStyle(isRecording ? Color.accentColor : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isRecording ? 1.5 : 0)
        )
    }

    private func toggleRecording() {
        if isRecording {
            recording = nil
            Switcher.shared.cancelRecording()
            return
        }
        if recording != nil { Switcher.shared.cancelRecording() }
        let id = shortcut.id
        recording = id
        Switcher.shared.recordShortcut { recorded in
            if recording == id { recording = nil }
            if let recorded { setKeys(recorded) }
        }
    }
}

/// A small label above a menu, for the shortcut's filters.
private struct FilterPicker<Value: Hashable & Identifiable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(options) { Text(label($0)).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 134, alignment: .leading)
        }
    }
}

private struct TrackpadCard: View {
    @Binding var gesture: GestureFingers
    @State private var conflict: SystemGestureConflict?

    var body: some View {
        HStack(spacing: 16) {
            TrackpadIllustration(fingers: gesture.count ?? 3, active: gesture != .off)
            VStack(alignment: .leading, spacing: 3) {
                Text("Trackpad Swipe").font(.system(size: 13, weight: .semibold))
                Text("Swipe left or right with several fingers to open the switcher and move through windows. Lift your fingers to switch.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let conflict {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message(conflict)).fixedSize(horizontal: false, vertical: true)
                            Button("Open System Settings") { NSWorkspace.shared.open(conflict.settingsURL) }
                                .buttonStyle(.link)
                        }
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            SegmentedChoice(selection: $gesture, options: [
                .init(value: .off, title: GestureFingers.off.title),
                .init(value: .three, title: "3"),
                .init(value: .four, title: "4"),
            ])
            .frame(width: 150)
        }
        .padding(16)
        .cardBackground()
        .onAppear(perform: refresh)
        .onChange(of: gesture) { refresh() }
        // Picks up changes made in System Settings while this window was in the background.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        conflict = gesture.count.flatMap { SystemGestureConflict.current(fingers: $0) }
    }

    private func message(_ conflict: SystemGestureConflict) -> String {
        switch (conflict, gesture) {
        case (.threeFingerDrag, _):
            String(localized: "Three-finger drag is on in macOS, so a three-finger swipe also drags. Turn it off in Accessibility → Pointer Control → Trackpad Options, or choose 4.")
        case (.fullScreenSwipe, .four):
            String(localized: "macOS also uses four-finger swipes to move between full-screen apps. Turn that off in Trackpad → More Gestures, or choose 3.")
        case (.fullScreenSwipe, _):
            String(localized: "macOS also uses three-finger swipes to move between full-screen apps. Turn that off in Trackpad → More Gestures, or choose 4.")
        }
    }
}

/// A trackpad with finger dots.
private struct TrackpadIllustration: View {
    let fingers: Int
    let active: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .frame(width: 92, height: 62)
            .overlay {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    HStack(spacing: 4) {
                        ForEach(0..<fingers, id: \.self) { _ in
                            Circle().fill(active ? Color.accentColor : Color.secondary.opacity(0.45)).frame(width: 11, height: 11)
                        }
                    }
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                }
            }
            .animation(.snappy(duration: 0.2), value: fingers)
            .animation(.snappy(duration: 0.2), value: active)
    }
}

/// What each key does while the switcher is open, with the keys drawn as they look on a Mac keyboard.
private struct SwitcherKeysGuide: View {
    let holdKeys: [MacKey]
    let keepOpen: Bool
    private let scale: CGFloat = 0.66

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                entry("Next window") { MacKey.tab(scale) }
                entry("Move around") { ArrowKeys(scale: scale) }
                entry("Close without switching") { MacKey.escape(scale) }
            }
            VStack(alignment: .leading, spacing: 10) {
                entry("Previous window") { HStack(spacing: 4) { MacKey.shift(scale); MacKey.tab(scale) } }
                entry(keepOpen ? "Switch to the selected window" : "Switch now (or let go of the keys)") { MacKey.returnKey(scale) }
                entry("Search windows and tabs") {
                    HStack(spacing: 5) {
                        Image(systemName: "character.cursor.ibeam").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("Type").font(.callout.weight(.medium))
                    }
                }
            }
        }
        .font(.callout)
    }

    private func entry<Keys: View>(_ title: LocalizedStringKey, @ViewBuilder keys: () -> Keys) -> some View {
        HStack(spacing: 12) {
            keys().frame(width: 118, alignment: .leading)
            Text(title).foregroundStyle(.primary)
        }
        .frame(minHeight: 30)
    }
}
