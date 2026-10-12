import AppKit
import SwiftUI

struct HelpSettings: View {
    /// The illustrations match the text, which describes the default ⌥ Option-Tab.
    private var shortcut: ShortcutConfig { ShortcutConfig.defaults[0] }

    var body: some View {
        SettingsPage {
            PageHeader(title: "Help", subtitle: "How GlideTab works, and answers to common questions.")

            HelpSection(title: "Switch windows") {
                SwitchIllustration(shortcut: shortcut)
            } content: {
                Step(number: 1, title: "Hold Option, press Tab", detail: "The switcher opens with your last window selected.") {
                    ShortcutKeys(shortcut: shortcut, scale: 0.55)
                }
                Step(number: 2, title: "Press Tab to move", detail: "Shift-Tab goes back. The arrow keys work too.")
                Step(number: 3, title: "Let go to switch", detail: "The selected window comes to the front.")
                Tip("Tap Option-Tab quickly to jump straight back to your last window.")
            }

            HelpSection(title: "The switcher at a glance") {
                AnnotatedSwitcher()
            } content: {
                Legend(number: 1, title: "Search bar", detail: "Type to filter. Matches are highlighted.")
                Legend(number: 2, title: "Selected window", detail: "Outlined in your accent color.")
                Legend(number: 3, title: "Status badges", detail: "Small icons next to the title.")
                Legend(number: 4, title: "Window buttons", detail: "Close, minimize or full screen, on hover.")
            }

            HelpSection(title: "Search") {
                SearchIllustration()
            } content: {
                Point(symbol: "character.cursor.ibeam", title: "Just type", detail: "No need to click. The list filters as you type.")
                Point(symbol: "text.magnifyingglass", title: "Finds titles, apps and tabs", detail: "Words can be in any order.")
                Point(symbol: "return", title: "Return switches, Esc closes", detail: "Once you type, the switcher stays open.")
                Tip("Example: **docs work** finds a Google Docs tab in your Work profile.")
            }

            HelpSection(title: "Browser tabs") {
                BrowserIllustration()
            } content: {
                Point(symbol: "globe", title: "Safari, Chrome, Brave, Edge, Vivaldi, Firefox", detail: "Including every Chrome profile.")
                Point(symbol: "checkmark.shield", title: "Allow once", detail: "macOS asks the first time. Click Allow.")
                Point(symbol: "slider.horizontal.3", title: "Choose when tabs appear", detail: "Off, when searching, or always, in Browsers.")
                Tip("Firefox shows tabs for windows on the current Space only.")
            }

            CardSection(title: "Status badges") {
                TableRow(symbol: "minus.circle", title: "Minimized", detail: "In the Dock. Switching brings it back.")
                RowDivider()
                TableRow(symbol: "eye.slash", title: "App hidden", detail: "Hidden with ⌘H. Switching shows it again.")
                RowDivider()
                TableRow(symbol: "square.on.square", title: "On another Space", detail: "On another desktop. Switching takes you there.")
                RowDivider()
                TableRow(symbol: "globe", title: "Browser tab", detail: "A tab that's not the visible one in its window.")
            }

            HelpSection(title: "Shortcuts and filters") {
                FiltersIllustration()
            } content: {
                Point(symbol: "keyboard", title: "Up to nine shortcuts", detail: "Each can show all windows, or only some.")
                Point(symbol: "app.badge", title: "Apps", detail: "All apps, or just the one you're using.")
                Point(symbol: "square.on.square", title: "Spaces and screens", detail: "All of them, or only the current one.")
                Point(symbol: "minus.circle", title: "Minimized and hidden", detail: "Show them, hide them, or list them last.")
            }

            HelpSection(title: "Trackpad swipe") {
                TrackpadSwipeIllustration()
            } content: {
                Point(symbol: "hand.draw", title: "Swipe to switch", detail: "Three or four fingers, left or right. Lift to switch.")
                Point(symbol: "command", title: "Turn it on in Shortcuts", detail: "It's off until you choose a finger count.")
                Tip("If macOS uses the same swipe for Spaces, pick the other number of fingers.")
            }

            CardSection(title: "Permissions", subtitle: "Everything stays on your Mac. No analytics.") {
                TableRow(symbol: "accessibility", title: "Accessibility", detail: "Required. Makes the shortcuts work and brings windows forward.")
                RowDivider()
                TableRow(symbol: "rectangle.dashed.badge.record", title: "Screen Recording", detail: "For thumbnails and previews. Still pictures only, never saved.")
                RowDivider()
                TableRow(symbol: "safari", title: "Automation", detail: "Asked once per browser, to read its tabs.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Questions").font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
                Card {
                    FAQ("The shortcut doesn't do anything.") {
                        Answer("Check that **Accessibility** shows Granted in General.")
                        Answer("Still nothing? In **System Settings → Privacy & Security → Accessibility**, turn GlideTab off and on again.")
                    }
                    RowDivider()
                    FAQ("Thumbnails show app icons instead of pictures.") {
                        Answer("Grant **Screen Recording** in General, then quit and reopen GlideTab.")
                        Answer("Minimized windows can't be pictured, so they show their last picture or the app icon.")
                    }
                    RowDivider()
                    FAQ("⌘Tab still opens the macOS app switcher.") {
                        Answer("Set a shortcut to **⌘ Command + Tab** in Shortcuts.")
                        Answer("GlideTab then turns the macOS switcher off, and turns it back on when you quit.")
                    }
                    RowDivider()
                    FAQ("A window I want is missing.") {
                        Answer("Check the shortcut's **filters** in Shortcuts.")
                        Answer("Make sure the app isn't set to **Hide windows** in Exceptions.")
                    }
                    RowDivider()
                    FAQ("Browser tabs don't appear.") {
                        Answer("Turn tabs on in **Browsers**.")
                        Answer("Allow GlideTab in **System Settings → Privacy & Security → Automation**.")
                        Answer("With the default setting, tabs appear once you start typing.")
                    }
                    RowDivider()
                    FAQ("A video flickers when the switcher opens.") {
                        Answer("Streaming sites protect their video, and macOS flickers it when a window picture is taken.")
                        Answer("Keep **Refresh thumbnails in the background** off, or use the **App Icons** or **List** style.")
                    }
                    RowDivider()
                    FAQ("How do I let an app keep the shortcut for itself?") {
                        Answer("In **Exceptions**, add the app and turn on **Ignore shortcuts**.")
                        Answer("Useful for remote desktops and virtual machines.")
                    }
                    RowDivider()
                    FAQ("Can I use GlideTab from Terminal?") {
                        Answer("Yes, with the **glidetab** command:")
                        Text("glidetab list\nglidetab focus <id>\nglidetab close <id>\nglidetab show")
                            .font(.system(size: 12, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                            .textSelection(.enabled)
                    }
                    RowDivider()
                    FAQ("How do I quit or remove GlideTab?") {
                        Answer("To quit, choose **Quit GlideTab** from its menu bar icon.")
                        Answer("To remove it, quit, drag it from Applications to the Trash, and remove it from **System Settings → General → Login Items**.")
                    }
                }
            }
        }
    }
}

// MARK: - Building blocks

/// A help topic: an illustration on the left, short points on the right.
private struct HelpSection<Illustration: View, Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var illustration: Illustration
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
            HStack(alignment: .top, spacing: 22) {
                illustration
                    .frame(width: 280, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .cardBackground()
        }
    }
}

private struct Marker: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.accentColor))
    }
}

/// A numbered step, optionally with keys drawn after it.
private struct Step<Accessory: View>: View {
    let number: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Marker(number: number)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory
        }
    }
}

extension Step where Accessory == EmptyView {
    init(number: Int, title: LocalizedStringKey, detail: LocalizedStringKey) {
        self.init(number: number, title: title, detail: detail) { EmptyView() }
    }
}

/// An icon, a short bold label and one line of detail.
private struct Point: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A short hint in a tinted box.
private struct Tip: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 1)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.6)))
    }
}

private struct Legend: View {
    let number: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Marker(number: number)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// A row in a two-column table: icon and name, then what it means.
private struct TableRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol)
            Text(title).fontWeight(.medium).frame(width: 160, alignment: .leading)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// One line of an FAQ answer.
private struct Answer: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(.secondary).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FAQ<Answer: View>: View {
    let question: LocalizedStringKey
    @ViewBuilder var answer: Answer
    @State private var expanded = false

    init(_ question: LocalizedStringKey, @ViewBuilder answer: () -> Answer) {
        self.question = question
        self.answer = answer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(question).fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 6) { answer }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Illustrations

private struct Backdrop<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            WallpaperBackdrop()
            content
        }
    }
}

private struct SwitchIllustration: View {
    let shortcut: ShortcutConfig

    var body: some View {
        VStack(spacing: 10) {
            ShortcutKeys(shortcut: shortcut, scale: 0.7)
            Image(systemName: "arrow.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Backdrop {
                MiniPanel {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in MiniWindow(icon: AppIcon.samples[i], selected: i == 1, scale: 0.75) }
                    }
                }
            }
            .frame(height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.4))
    }
}

private struct AnnotatedSwitcher: View {
    var body: some View {
        Backdrop {
            MiniPanel {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text("Search windows").font(.system(size: 9)).foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.primary.opacity(0.06)))
                    .overlay(alignment: .trailing) { Marker(number: 1).offset(x: 9) }
                    HStack(spacing: 3) {
                        MiniWindow(icon: AppIcon.samples[0], scale: 0.8)
                            .overlay(alignment: .topLeading) {
                                WindowButtonDots(spacing: 2)
                                .frame(width: 18, height: 5)
                                .offset(x: 7, y: 15)
                            }
                            .overlay(alignment: .bottomLeading) { Marker(number: 4).offset(x: -4, y: 6) }
                        MiniWindow(icon: AppIcon.samples[1], selected: true, scale: 0.8)
                            .overlay(alignment: .bottom) { Marker(number: 2).offset(y: 8) }
                        MiniWindow(icon: AppIcon.samples[2], scale: 0.8)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "minus.circle").font(.system(size: 7)).foregroundStyle(.secondary).offset(x: -4, y: 4)
                            }
                            .overlay(alignment: .topTrailing) { Marker(number: 3).offset(x: 8, y: -8) }
                    }
                }
                .frame(width: 190)
            }
        }
    }
}

private struct SearchIllustration: View {
    var body: some View {
        Backdrop {
            MiniPanel {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text("docs").font(.system(size: 11))
                        Rectangle().fill(Color.accentColor).frame(width: 1.5, height: 11)
                        Spacer()
                        Text("2 of 9").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.primary.opacity(0.06)))
                    resultRow("com.google.Chrome", before: "Q3 Planning – Google ", match: "Docs", after: "", selected: true)
                    resultRow("com.apple.Notes", before: "Meeting ", match: "docs", after: " checklist", selected: false)
                }
                .frame(width: 200)
            }
        }
    }

    private func resultRow(_ bundleID: String, before: String, match: String, after: String, selected: Bool) -> some View {
        var highlighted = AttributedString(match)
        highlighted.backgroundColor = Color(nsColor: .findHighlightColor)
        highlighted.foregroundColor = .black
        return HStack(spacing: 5) {
            Image(nsImage: AppIcon.of(bundleID)).resizable().frame(width: 12, height: 12)
            Text(AttributedString(before) + highlighted + AttributedString(after))
                .font(.system(size: 9.5))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(height: 18)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.2))
    }
}

private struct BrowserIllustration: View {
    var body: some View {
        Backdrop {
            MiniPanel {
                VStack(spacing: 3) {
                    SampleTabRow(bundleID: "com.google.Chrome", title: "Inbox – Gmail", detail: "Work · mail.google.com",
                                 selected: true, scale: 0.8)
                    SampleTabRow(bundleID: "com.google.Chrome", title: "Pull requests", detail: "Personal · github.com", scale: 0.8)
                    SampleTabRow(bundleID: "com.apple.Safari", title: "Weather", detail: "weather.com", scale: 0.8)
                }
                .frame(width: 220)
            }
        }
    }
}

private struct FiltersIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Apps", "All Apps")
            row("Spaces", "Current Space")
            row("Screens", "All Screens")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.4))
    }

    private func row(_ title: LocalizedStringKey, _ value: LocalizedStringKey) -> some View {
        HStack {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Text(value).font(.system(size: 11))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(nsColor: .controlColor)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}

private struct TrackpadSwipeIllustration: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.4))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .frame(width: 170, height: 110)
            HStack(spacing: 10) {
                Image(systemName: "arrow.left").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.accentColor).frame(width: 15, height: 15) }
                }
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
    }
}
