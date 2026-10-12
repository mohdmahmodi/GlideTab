import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettings: View {
    @AppStorage(Prefs.Key.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Prefs.Key.autoUpdate) private var autoUpdate = true
    @AppStorage(Prefs.Key.commandLine) private var commandLine = false
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var language = Prefs.language ?? ""
    @State private var accessibility = Permissions.accessibility
    @State private var screenRecording = Permissions.screenRecording

    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPage {
            header

            CardSection(title: "Startup") {
                SettingRow(title: "Open at login", detail: "Start GlideTab when you log in.", icon: "power") {
                    Toggle("Open at login", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                SettingRow(title: "Show in menu bar", detail: showMenuBarIcon ? nil : "Open GlideTab again from Finder or Spotlight to get back here.",
                           icon: "menubar.rectangle") {
                    Toggle("Show in menu bar", isOn: $showMenuBarIcon).labelsHidden().toggleStyle(.switch)
                }
            }

            CardSection(title: "Language & Updates") {
                SettingRow(title: "Language", icon: "globe") {
                    Picker("Language", selection: $language) {
                        Text("System Default").tag("")
                        Divider()
                        ForEach(Prefs.languages, id: \.self) { code in
                            Text(Locale(identifier: code).localizedString(forIdentifier: code)?.localizedCapitalized ?? code).tag(code)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                RowDivider()
                SettingRow(title: "Check for updates automatically", detail: "Once a day. Updates are verified before installing.",
                           icon: "arrow.triangle.2.circlepath") {
                    Toggle("Check for updates automatically", isOn: $autoUpdate).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                SettingRow(title: "Command line tool", detail: "Lets the glidetab command list and switch windows. While on, any app you run can use it too.",
                           icon: "terminal") {
                    Toggle("Command line tool", isOn: $commandLine).labelsHidden().toggleStyle(.switch)
                }
            }

            CardSection(title: "Permissions", subtitle: "GlideTab only asks for what its features need. Nothing leaves your Mac.") {
                PermissionRow(title: "Accessibility", detail: "For the shortcuts and switching windows.", icon: "accessibility",
                              granted: accessibility) {
                    Permissions.requestAccessibility()
                    Permissions.openSettings("Privacy_Accessibility")
                }
                RowDivider()
                PermissionRow(title: "Screen Recording", detail: "For thumbnails and previews. Not needed for App Icons or List.",
                              icon: "rectangle.dashed.badge.record", granted: screenRecording, action: Permissions.requestScreenRecording)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Export Settings…", action: exportSettings)
                Button("Import Settings…", action: importSettings)
                Button("Reset Settings…", action: resetSettings)
            }
            .controlSize(.regular)
        }
        .onReceive(refresh) { _ in
            accessibility = Permissions.accessibility
            screenRecording = Permissions.screenRecording
            launchAtLogin = LoginItem.isEnabled
        }
        .onChange(of: launchAtLogin) { _, new in
            guard new != LoginItem.isEnabled else { return }
            LoginItem.isEnabled = new
            // Registering can fail (or need approval in System Settings): show what actually happened.
            DispatchQueue.main.async { launchAtLogin = LoginItem.isEnabled }
        }
        .onChange(of: showMenuBarIcon) { _, _ in (NSApp.delegate as? AppDelegate)?.updateStatusItem() }
        .onChange(of: autoUpdate) { _, _ in Updater.shared.start() }
        .onChange(of: commandLine) { _, new in CLI.setEnabled(new) }
        .onChange(of: language) { _, new in
            Prefs.language = new.isEmpty ? nil : new
            askToRelaunch(String(localized: "Relaunch GlideTab to use the new language."))
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text("GlideTab").font(.system(size: 20, weight: .semibold))
                Text("Version \(Updater.shared.currentVersion)").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Check for Updates") { Updater.shared.check(userInitiated: true) }
                .controlSize(.large)
        }
        .padding(16)
        .cardBackground()
    }

    private func exportSettings() {
        let save = NSSavePanel()
        save.nameFieldStringValue = "GlideTab Settings.plist"
        save.allowedContentTypes = [.propertyList]
        if save.runModal() == .OK, let url = save.url {
            report { try Prefs.exportSettings(to: url) }
        }
    }

    private func importSettings() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.propertyList]
        if open.runModal() == .OK, let url = open.url {
            report {
                try Prefs.importSettings(from: url)
                AppDelegate.relaunch()
            }
        }
    }

    private func report(_ action: () throws -> Void) {
        do { try action() } catch { NSAlert(error: error).runModal() }
    }

    private func resetSettings() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Reset all settings?")
        alert.informativeText = String(localized: "Shortcuts, appearance and exceptions go back to their defaults, and GlideTab relaunches.")
        alert.addButton(withTitle: String(localized: "Reset"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Prefs.resetSettings()
        AppDelegate.relaunch()
    }

    private func askToRelaunch(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: String(localized: "Relaunch Now"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn { AppDelegate.relaunch() }
    }
}

struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let icon: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        SettingRow(title: title, detail: detail, icon: icon) {
            if granted {
                StatusPill(text: "Granted")
            } else {
                Button("Grant Access…", action: action)
            }
        }
    }
}
