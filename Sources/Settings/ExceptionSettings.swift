import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExceptionSettings: View {
    @State private var exceptions = Prefs.exceptions
    @State private var selection: String? = Prefs.exceptions.first?.bundleID

    var body: some View {
        SettingsPage {
            VStack(alignment: .leading, spacing: 2) {
                Text("Exceptions").font(.system(size: 13, weight: .semibold))
                Text("Rules for specific apps: keep their windows out of the switcher, or let them use the shortcuts themselves.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.leading, 4)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(exceptions) { exception in
                                MasterRow(title: AppIcon.name(exception.bundleID), subtitle: summary(exception),
                                          icon: AppIcon.of(exception.bundleID), isSelected: selection == exception.bundleID) {
                                    selection = exception.bundleID
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(width: 280, height: 410)
                    .cardBackground()
                    AddRemoveBar(canRemove: selection != nil, add: add, remove: remove)
                }

                Group {
                    if let index = exceptions.firstIndex(where: { $0.bundleID == selection }) {
                        ExceptionDetail(exception: $exceptions[index])
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "hand.raised").font(.system(size: 30)).foregroundStyle(.tertiary)
                            Text("Add an app with +").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .cardBackground()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .onChange(of: exceptions) { _, new in Prefs.exceptions = new }
    }

    private func summary(_ exception: AppException) -> String {
        var parts: [String] = []
        if exception.hideWindows { parts.append(String(localized: "Hidden")) }
        if exception.ignoreShortcuts { parts.append(String(localized: "Ignores shortcuts")) }
        return parts.isEmpty ? String(localized: "No rules") : parts.joined(separator: " · ")
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
            if !exceptions.contains(where: { $0.bundleID == id }) { exceptions.insert(AppException(bundleID: id), at: 0) }
            selection = id
        }
    }

    private func remove() {
        guard let index = exceptions.firstIndex(where: { $0.bundleID == selection }) else { return }
        exceptions.remove(at: index)
        selection = exceptions.indices.contains(index) ? exceptions[index].bundleID : exceptions.last?.bundleID
    }
}

private struct ExceptionDetail: View {
    @Binding var exception: AppException

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: AppIcon.of(exception.bundleID)).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppIcon.name(exception.bundleID)).font(.system(size: 17, weight: .semibold))
                    Text(exception.bundleID).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    if !AppIcon.isInstalled(exception.bundleID) {
                        Text("Not installed").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(16)
            .cardBackground()

            Card {
                SettingRow(title: "Hide windows", detail: "Never show this app's windows in the switcher.", icon: "eye.slash") {
                    Toggle("Hide windows", isOn: $exception.hideWindows).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                SettingRow(title: "Ignore shortcuts", detail: "While this app is in front, it gets the shortcut keys. Useful for remote desktops and virtual machines.",
                           icon: "keyboard.badge.ellipsis") {
                    Toggle("Ignore shortcuts", isOn: $exception.ignoreShortcuts).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }
}
