import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var accessibilityTimer: Timer?
    private var started = false
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        // Never let a frozen app stall the switcher for long.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        #if DEBUG
        if Debug.run() { return }
        #endif
        // A second copy (say, a new download opened while the old one runs) hands over to the first and quits.
        if let other = AppMover.otherInstances.first {
            // Only an established copy gets the reopen, so two fresh copies can't keep launching each other.
            if let url = other.bundleURL, (other.launchDate ?? .distantPast) < Date(timeIntervalSinceNow: -3) {
                NSWorkspace.shared.open(url)
            }
            NSApp.terminate(nil)
            return
        }
        // Opened straight from Downloads: offer to move to Applications first, where updates can install.
        if AppMover.offerAtLaunch() { return }

        updateStatusItem()
        CLI.setEnabled(Prefs.commandLine)
        // New installs register the login item when setup ends, so nothing appears before the setup window.
        if !Onboarding.isNeeded, !UserDefaults.standard.bool(forKey: Prefs.Key.didSetUpLoginItem) {
            UserDefaults.standard.set(true, forKey: Prefs.Key.didSetUpLoginItem)
            LoginItem.isEnabled = true
        }
        // Undo a ⌘Tab takeover left by a crashed run; Switcher.start takes it over again once the tap is live.
        Private.setNativeCommandTab(enabled: true)
        restoreCommandTabOnSignals()
        Updater.shared.start()

        // Explain the permissions before macOS asks for them. Also reopens after the Screen Recording relaunch.
        if Onboarding.isNeeded { showOnboarding() }
        if Permissions.accessibility {
            start()
        } else {
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard Permissions.accessibility else { return }
                timer.invalidate()
                self?.start()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Private.setNativeCommandTab(enabled: true)
    }

    /// Quitting from Activity Monitor or `kill` skips applicationWillTerminate; give the system ⌘Tab back anyway.
    private func restoreCommandTabOnSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                Private.setNativeCommandTab(enabled: true)
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Opening the app again (e.g. from Finder or Spotlight) shows Settings, which matters when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Onboarding.isNeeded { showOnboarding() } else { showSettings() }
        return false
    }

    private func start() {
        guard !started else { return }
        // Set again now that Accessibility is on: on a first launch, the call at startup came before it was.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        guard Switcher.shared.start() else {
            // Accessibility can take a moment to apply after being granted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.start() }
            return
        }
        started = true
        WindowManager.shared.start()
        BrowserTabs.shared.start()
    }

    // MARK: Menu bar

    func updateStatusItem() {
        guard Prefs.showMenuBarIcon else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "GlideTab")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !Permissions.accessibility || (Prefs.style == .thumbnails && !Permissions.screenRecording) {
            let warning = menu.addItem(withTitle: String(localized: "Permissions Needed…"),
                                       action: Onboarding.isNeeded ? #selector(showOnboarding) : #selector(showSettings), keyEquivalent: "")
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            warning.target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: String(localized: "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "About GlideTab"), action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit GlideTab"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = SettingsWindow.make()
            window.delegate = self
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showOnboarding() {
        if onboardingWindow == nil {
            let window = Onboarding.makeWindow { [weak self] in self?.onboardingWindow?.close() }
            window.delegate = self
            onboardingWindow = window
        }
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    /// Quits and reopens the app (from `url`, if it moved). The helper waits for this process to exit, so `open`
    /// starts a fresh copy.
    static func relaunch(at url: URL = Bundle.main.bundleURL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; open \"$0\"",
                          url.path, String(ProcessInfo.processInfo.processIdentifier)]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func checkForUpdates() {
        Updater.shared.check(userInitiated: true)
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: String(localized: "A lightweight window switcher."),
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }

    /// Closing setup once GlideTab can work counts as finishing it, so it doesn't reopen at every login.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === onboardingWindow, Permissions.accessibility { Onboarding.finish() }
        return true
    }

    /// Drop the Settings window when closed so nothing in it keeps running in the background.
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            Switcher.shared.cancelRecording()
            settingsWindow = nil
        } else if (notification.object as? NSWindow) === onboardingWindow {
            onboardingWindow = nil
        }
    }
}
