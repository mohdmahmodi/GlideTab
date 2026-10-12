import AppKit

/// An app opened straight from Downloads runs from a read-only copy that macOS makes for it (App Translocation),
/// where it can't update itself. This offers to move GlideTab to Applications and reopen it from there.
enum AppMover {
    /// Opened from Downloads, the Desktop or a disk image rather than an Applications folder.
    static var isOutsideApplications: Bool {
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") { return true }
        let home = NSHomeDirectory()
        return ["\(home)/Downloads/", "\(home)/Desktop/"].contains { path.hasPrefix($0) }
    }

    /// Asks once at launch. Returns true if GlideTab is moving and about to reopen.
    static func offerAtLaunch() -> Bool {
        guard isOutsideApplications, !UserDefaults.standard.bool(forKey: Prefs.Key.declinedMove) else { return false }
        if offer(String(localized: "GlideTab works best from the Applications folder. There it can update itself, and it stays put when you clean up Downloads.")) {
            return true
        }
        UserDefaults.standard.set(true, forKey: Prefs.Key.declinedMove)
        return false
    }

    /// Asks with `message`, and moves and reopens GlideTab if the person agrees. Returns true if it's moving.
    static func offer(_ message: String) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Move GlideTab to Applications?")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Later"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        guard let destination = move() else {
            let failure = NSAlert()
            failure.messageText = String(localized: "GlideTab couldn't be moved. Drag it to the Applications folder in Finder, then open it from there.")
            failure.runModal()
            return false
        }
        AppDelegate.relaunch(at: destination)
        return true
    }

    /// Copies the running app into Applications (or ~/Applications if that isn't writable) and moves the
    /// original to the Trash. Returns the new location. If a copy in Applications is already running, that one
    /// is used as is.
    static func move() -> URL? {
        let fm = FileManager.default
        let source = Bundle.main.bundleURL
        let name = source.lastPathComponent
        let folders = [URL(fileURLWithPath: "/Applications"),
                       fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for folder in folders {
            let destination = folder.appendingPathComponent(name)
            // A copy that's already running, or at least as new as this one, is used as is.
            if isRunning(destination) { return destination }
            if let there = Bundle(url: destination), buildNumber(there) >= buildNumber(.main) {
                trashOriginal(unless: destination)
                return destination
            }
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                if fm.fileExists(atPath: destination.path) { try fm.trashItem(at: destination, resultingItemURL: nil) }
                try fm.copyItem(at: source, to: destination)
            } catch {
                continue
            }
            // This copy already passed Gatekeeper when it was opened. Without the quarantine flag, macOS runs the
            // new copy where it is instead of translocating it again.
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
            try? xattr.run()
            xattr.waitUntilExit()
            trashOriginal(unless: destination)
            return destination
        }
        return nil
    }

    private static func buildNumber(_ bundle: Bundle) -> Int {
        Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    /// Moves the copy this app was opened from to the Trash. macOS may ask for access to Downloads first; if
    /// that's declined, the copy stays and the move still counts.
    private static func trashOriginal(unless destination: URL) {
        guard let original = originalURL, original.standardizedFileURL != destination.standardizedFileURL else { return }
        do {
            try FileManager.default.trashItem(at: original, resultingItemURL: nil)
        } catch {
            NSLog("GlideTab: couldn't move the original to the Trash: %@", error.localizedDescription)
        }
    }

    /// Another GlideTab process running from `url`.
    static func isRunning(_ url: URL) -> Bool {
        otherInstances.contains { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
    }

    /// Other running copies of GlideTab, whatever folder they're in.
    static var otherInstances: [NSRunningApplication] {
        guard let id = Bundle.main.bundleIdentifier else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != me }
    }

    /// Where a translocated app really is (e.g. ~/Downloads/GlideTab.app), or the app itself if it isn't translocated.
    private static var originalURL: URL? {
        let url = Bundle.main.bundleURL
        guard url.path.contains("/AppTranslocation/") else { return url }
        typealias Original = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let original = unsafeBitCast(symbol, to: Original.self)
        return original(url as CFURL, nil)?.takeRetainedValue() as URL?
    }
}
