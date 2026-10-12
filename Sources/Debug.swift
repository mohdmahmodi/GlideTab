// Developer commands. Compiled only into debug builds (GLIDETAB_DEBUG=1 ./build.sh …), never into releases:
// they use the app's permissions on behalf of whoever launches it.
#if DEBUG
import AppKit
import ScreenCaptureKit
import SwiftUI

/// Developer commands (run against the installed app so it uses its own permissions):
///
///     open -W --stdout out.txt GlideTab.app --args --dump
///     open -W GlideTab.app --args --snapshot panel.png [-style list] [--query text] [--dark | --light] [--hover]
///     open -W GlideTab.app --args --snapshot settings.png --settings [--tab 0…5]
///     open -W GlideTab.app --args --snapshot welcome.png --onboarding [-onboarding accessibility|previews|ready]
///         Either form also takes [--backdrop image] [--only bundle.id,bundle.id] for clean screenshots.
///     open -W --stdout out.txt GlideTab.app --args --stress        (never focuses anything)
///     open -W --stdout out.txt GlideTab.app --args --e2e           (really switches windows, then restores)
///     open -W --stdout out.txt GlideTab.app --args --toggle        (quick ⌥Tab taps between the last two windows)
///
/// `-style …` uses the UserDefaults argument domain, so it overrides the setting without saving it.
enum Debug {
    private static var window: NSWindow?
    private static var backdropWindow: NSWindow?

    /// Returns true if a debug command is running (the app exits when it's done).
    static func run() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if args.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }

        if args.contains("--dump") {
            dump()
        } else if args.contains("--stress") {
            // From a timer, not a main-queue block: the test spins the run loop, and main-queue work can't
            // run while another main-queue block is executing.
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in StressTest.run() }
        } else if args.contains("--toggle") {
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in ToggleTest.run() }
        } else if args.contains("--e2e") {
            DispatchQueue.main.async { EndToEndTest.run() }
        } else if let path = value("--snapshot") {
            snapshot(to: path, args: args, tab: value("--tab").flatMap(Int.init), query: value("--query") ?? "")
        } else {
            return false
        }
        return true
    }

    /// The focused window of the frontmost app.
    static func focusedWindowID() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier).element(kAXFocusedWindowAttribute)?.windowID
    }

    private static func value(_ flag: String, in args: [String] = CommandLine.arguments) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    private static func dump() {
        print("accessibility=\(Permissions.accessibility) screenRecording=\(Permissions.screenRecording)")
        for w in WindowManager.shared.currentWindows() {
            print("\(w.id)\t\(w.appName)\t\(w.displayTitle)\tminimized=\(w.isMinimized) hidden=\(w.app.isHidden) otherSpace=\(w.isOnOtherSpace) ax=\(w.ax != nil)")
        }
        BrowserTabs.shared.refreshAll {
            let windows = WindowManager.shared.currentWindows()
            for tab in BrowserTabs.shared.backgroundTabs(in: windows) {
                print("tab\t\(tab.app.localizedName ?? "")\t\(tab.title)\t\(tab.host)\tprofile=\(tab.profile ?? "-") window=\(tab.window?.id ?? 0)")
            }
            exit(0)
        }
    }

    private static func snapshot(to path: String, args: [String], tab: Int?, query: String) {
        if let image = value("--backdrop") { showBackdrop(image) }
        let only = value("--only").map { Set($0.split(separator: ",").map(String.init)) }
        if args.contains("--live") {
            // The real switcher, with the selected-window preview, captured full screen.
            Switcher.shared.isDryRun = true
            Switcher.shared.showPinned()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                print("switcher state at capture: \(Switcher.shared.state)")
                let screen = NSScreen.main!
                let frame = NSWindow(contentRect: screen.frame.insetBy(dx: 30, dy: 30), styleMask: .borderless, backing: .buffered, defer: true)
                capture(frame, to: path, screen: screen)
            }
            return
        }
        if args.contains("--onboarding") {
            let onboarding = Onboarding.makeWindow {}
            onboarding.level = .floating
            NSApp.activate()
            onboarding.makeKeyAndOrderFront(nil)
            window = onboarding
            // Drawn from the view itself, so it doesn't need Screen Recording.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let view = onboarding.contentView?.superview,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                exit(0)
            }
            return
        }
        if args.contains("--settings") {
            let settings = SettingsWindow.make()
            if let tab, let tabs = settings.contentViewController as? NSTabViewController { tabs.selectedTabViewItemIndex = tab }
            settings.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] // visible even over a full-screen app
            settings.level = .floating
            settings.orderFrontRegardless()
            window = settings
        } else {
            let windows = WindowManager.shared.currentWindows().filter(Prefs.includes)
                .filter { only?.contains($0.app.bundleIdentifier ?? "") ?? true }
            let panel = SwitcherPanel()
            window = panel
            Thumbnails.shared.capture(windows)
            BrowserTabs.shared.refreshAll {
                var items = windows.map(SwitcherItem.window)
                if !query.isEmpty || Prefs.browserTabs == .always {
                    items += BrowserTabs.shared.backgroundTabs(in: windows).map(SwitcherItem.tab)
                }
                let total = items.count
                items = items.filter { $0.matches(query) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let selected = min(1, max(items.count - 1, 0))
                    panel.present(items, selected: selected, query: query, total: total, style: Prefs.style, on: NSScreen.main!)
                    if args.contains("--hover") { panel.showHoverControls(at: selected) }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { capture(window!, to: path) }
    }

    /// Covers the screen with an image, so screenshots show a clean desktop instead of whatever is open.
    private static func showBackdrop(_ path: String) {
        guard let screen = NSScreen.main, let image = NSImage(contentsOfFile: path) else { return }
        let backdrop = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        let view = NSView()
        view.wantsLayer = true
        view.layer?.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        view.layer?.contentsGravity = .resizeAspectFill
        backdrop.contentView = view
        backdrop.level = NSWindow.Level(NSWindow.Level.floating.rawValue - 1)
        backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backdrop.orderFrontRegardless()
        backdropWindow = backdrop
    }

    /// Captures the screen area under `window` (so the translucent background looks real) to a PNG.
    private static func capture(_ window: NSWindow, to path: String, screen: NSScreen? = nil) {
        guard let screen = screen ?? window.screen else { exit(1) }
        let frame = window.frame.insetBy(dx: -30, dy: -30)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content?.displays.first(where: { $0.displayID == displayID }) else { exit(1) }
            let config = SCStreamConfiguration()
            config.sourceRect = CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY,
                                       width: frame.width, height: frame.height)
            config.width = Int(frame.width * screen.backingScaleFactor)
            config.height = Int(frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []),
                                             configuration: config) { image, error in
                guard let image else {
                    print("capture failed: \(String(describing: error))")
                    exit(1)
                }
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path))
                exit(0)
            }
        }
    }
}

/// Measures memory in megabytes (resident footprint).
func residentMegabytes() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

/// Drives the real switcher (panel, search, rendering) with thousands of synthetic key events, without
/// ever focusing a window, and checks it always returns to a clean idle state.
enum StressTest {
    private static func drain(_ seconds: Double = 0.002) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Spins the run loop until everything already queued on the main queue has run.
    private static func flush() {
        var done = false
        DispatchQueue.main.async { done = true }
        let deadline = Date().addingTimeInterval(5)
        while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
    }

    static func run() {
        Switcher.shared.isDryRun = true
        var failures: [String] = []
        let start = Date()
        let memoryBefore = residentMegabytes()
        var rng = SystemRandomNumberGenerator()
        let option = CGEventFlags.maskAlternate
        let sessions = max(UserDefaults.standard.integer(forKey: "stressSessions"), 400)
        var checkpoints: [String] = []

        for session in 0..<sessions { autoreleasepool {
            Switcher.shared.feed(KeyInput(kind: .flagsChanged, flags: option))
            Switcher.shared.feed(KeyInput(kind: .keyDown, keyCode: KeyCode.tab, flags: option))
            Switcher.shared.feed(KeyInput(kind: .keyUp, keyCode: KeyCode.tab, flags: option))
            drain(session % 10 == 0 ? 0.15 : 0.002) // sometimes long enough for the panel to appear
            for _ in 0..<Int.random(in: 0...12, using: &rng) {
                let step = Int.random(in: 0..<8, using: &rng)
                let (key, character): (Int64, Character?) = switch step {
                case 0: (KeyCode.tab, nil)
                case 1: (KeyCode.left, nil)
                case 2: (KeyCode.right, nil)
                case 3: (KeyCode.down, nil)
                case 4: (KeyCode.up, nil)
                case 5: (KeyCode.delete, nil)
                default: (0, Character(String("abcdefghijklmnopqrstuvwxyz ".randomElement(using: &rng)!)))
                }
                let shift: CGEventFlags = Bool.random(using: &rng) ? .maskShift : []
                Switcher.shared.feed(KeyInput(kind: .keyDown, keyCode: key, flags: option.union(shift), character: character))
                Switcher.shared.feed(KeyInput(kind: .keyUp, keyCode: key, flags: option.union(shift)))
                if Bool.random(using: &rng) { drain() }
            }
            // End the session one of three ways.
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: Switcher.shared.feed(KeyInput(kind: .keyDown, keyCode: KeyCode.escape, flags: option))
            case 1: Switcher.shared.feed(KeyInput(kind: .keyDown, keyCode: KeyCode.returnKey, flags: option))
            default: break
            }
            Switcher.shared.feed(KeyInput(kind: .flagsChanged, flags: []))
            flush()
            // Typing pins the switcher open. Esc clears a search first, so at most two presses must close it.
            for _ in 0..<2 where Switcher.shared.state.isOpen {
                Switcher.shared.feed(KeyInput(kind: .keyDown, keyCode: KeyCode.escape))
                flush()
            }
            if (session + 1) % 500 == 0 { checkpoints.append(String(format: "%d: %.1f MB", session + 1, residentMegabytes())) }
            let state = Switcher.shared.state
            if state.isOpen || state.isShown || state.keyboardActive {
                failures.append("session \(session): not idle afterwards: \(state)")
            }
        } }
        let switcherTime = Date().timeIntervalSince(start)

        let memoryBeforeTyping = residentMegabytes()
        // Typing speed: how long each keystroke takes to update the open switcher on screen.
        Switcher.shared.showPinned()
        flush()
        drain(0.3)
        var keystrokeTimes: [Double] = []
        for i in 0..<300 {
            let begin = Date()
            if i % 4 == 3 {
                Switcher.shared.feed(KeyInput(kind: .keyDown, keyCode: KeyCode.delete))
            } else {
                Switcher.shared.feed(KeyInput(kind: .keyDown, keyCode: 0, character: Character(String("aeiourst".randomElement()!))))
            }
            flush()
            keystrokeTimes.append(Date().timeIntervalSince(begin) * 1000)
        }
        Switcher.shared.feed(KeyInput(kind: .keyDown, keyCode: KeyCode.escape))
        flush()
        keystrokeTimes.sort()
        print(String(format: "  memory around typing:   %.1f MB before, %.1f MB after", memoryBeforeTyping, residentMegabytes()))
        // The window server hands back the panel's drawing buffers a moment after it closes, so look again.
        drain(2)
        print(String(format: "  memory 2 s after typing: %.1f MB", residentMegabytes()))
        let memoryAfterSwitcher = residentMegabytes()

        // Window listing speed.
        let listStart = Date()
        var count = 0
        for _ in 0..<100 { count = WindowManager.shared.currentWindows().count }
        let listTime = Date().timeIntervalSince(listStart) / 100

        print("GlideTab stress test")
        print("  switcher sessions:      \(sessions) in \(String(format: "%.1f", switcherTime))s, failures: \(failures.count)")
        failures.prefix(10).forEach { print("    \($0)") }
        print("  memory:                 \(String(format: "%.1f", memoryBefore)) MB → \(String(format: "%.1f", memoryAfterSwitcher)) MB")
        if !checkpoints.isEmpty { print("  memory by session:      \(checkpoints.joined(separator: ", "))") }
        print("  keystroke → screen:     median \(String(format: "%.2f", keystrokeTimes[keystrokeTimes.count / 2])) ms, 99th percentile \(String(format: "%.2f", keystrokeTimes[keystrokeTimes.count * 99 / 100])) ms")
        print("  list \(count) windows:       \(String(format: "%.1f", listTime * 1000)) ms average over 100 runs")

        // Browser tab refresh speed (the second read is the steady state: scripts compiled, browsers warm).
        let tabStart = Date()
        BrowserTabs.shared.refreshAll(force: true) {
            let cold = Date().timeIntervalSince(tabStart)
            let warmStart = Date()
            BrowserTabs.shared.refreshAll(force: true) {
            let tabs = BrowserTabs.shared.backgroundTabs(in: WindowManager.shared.currentWindows()).count
            print("  browser tabs:           \(tabs) background tabs, first read \(String(format: "%.0f", cold * 1000)) ms, then \(String(format: "%.0f", Date().timeIntervalSince(warmStart) * 1000)) ms")
            // Thumbnail memory stays bounded across repeated captures.
            let windows = WindowManager.shared.currentWindows()
            var rounds = 0
            func captureRound() {
                Thumbnails.shared.capture(windows)
                rounds += 1
                if rounds < 20 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: captureRound)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        print("  20 thumbnail rounds:    \(Thumbnails.shared.cache.count) cached, memory \(String(format: "%.1f", residentMegabytes())) MB")
                        print(failures.isEmpty ? "PASS" : "FAIL")
                        exit(failures.isEmpty ? 0 : 1)
                    }
                }
            }
            captureRound()
            }
        }
    }
}

/// Really focuses each visible window (and a background browser tab), checks it landed, then restores.
enum EndToEndTest {
    static func run() {
        let all = WindowManager.shared.currentWindows()
        let original = all.first
        let targets = Array(all.filter { !$0.isMinimized && !$0.app.isHidden }.prefix(8))
        var results: [(String, Bool)] = []
        var index = 0

        func next() {
            guard index < targets.count else { return testTab() }
            let target = targets[index]
            index += 1
            WindowManager.shared.focus(target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                let ok = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid && Debug.focusedWindowID() == target.id
                results.append(("\(target.appName) — \(target.displayTitle.prefix(40))\(target.isOnOtherSpace ? " [other Space]" : "")", ok))
                next()
            }
        }

        func testTab() {
            BrowserTabs.shared.refreshAll(force: true) {
                let windows = WindowManager.shared.currentWindows()
                guard let tab = BrowserTabs.shared.backgroundTabs(in: windows).first(where: { $0.window != nil && !$0.title.isEmpty }),
                      let window = tab.window else {
                    results.append(("browser tab (none available)", true))
                    return finish()
                }
                let previousTitle = window.title
                BrowserTabs.shared.select(tab) {
                    WindowManager.shared.focus(window)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        let title = AXUIElementCreateApplication(window.pid).element(kAXFocusedWindowAttribute)?.string(kAXTitleAttribute) ?? ""
                        let ok = title.hasPrefix(tab.title.prefix(20))
                        results.append(("browser tab \"\(tab.title.prefix(40))\" (window now \"\(title.prefix(40))\")", ok))
                        if !ok { print("  raw tab list: \(BrowserTabs.shared.rawTabList(tab.app).prefix(600))") }
                        // Put the original tab back.
                        BrowserTabs.shared.refreshAll(force: true) {
                            let tabs = BrowserTabs.shared.backgroundTabs(in: WindowManager.shared.currentWindows())
                            if let back = tabs.first(where: { $0.window?.id == window.id && previousTitle.hasPrefix($0.title) }) {
                                BrowserTabs.shared.select(back) { finish() }
                            } else {
                                finish()
                            }
                        }
                    }
                }
            }
        }

        func finish() {
            if let original { WindowManager.shared.focus(original) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                print("GlideTab end-to-end test")
                for (name, ok) in results { print("  \(ok ? "✓" : "✗") \(name)") }
                let passed = results.allSatisfy(\.1)
                print(passed ? "PASS" : "FAIL")
                exit(passed ? 0 : 1)
            }
        }

        next()
    }
}

/// Real quick-⌥Tab toggling through the switcher: each tap must land on the other of the last two windows.
enum ToggleTest {
    static func run() {
        let windows = WindowManager.shared.currentWindows().filter { !$0.isMinimized && !$0.app.isHidden }
        guard windows.count >= 2, let start = Debug.focusedWindowID() else {
            print("need two windows")
            exit(1)
        }
        let first = start, second = windows.first { $0.id != start }!.id
        var expected = second
        var results: [(ok: Bool, ms: Double)] = []
        // Use the user's first all-apps shortcut.
        let all = Prefs.shortcuts.filter { $0.apps == .all }
        let pick = UserDefaults.standard.integer(forKey: "toggleShortcut") // -toggleShortcut N picks the Nth all-apps shortcut
        let shortcut = all.indices.contains(pick) ? all[pick] : (all.first ?? ShortcutConfig.defaults[0])
        let option = shortcut.holdFlags
        print("  using \(shortcut.displayString)")

        func tap(_ remaining: Int) {
            guard remaining > 0 else { return finish() }
            let began = Date()
            Switcher.shared.feed(KeyInput(kind: .flagsChanged, flags: option))
            Switcher.shared.feed(KeyInput(kind: .keyDown, keyCode: shortcut.keyCode, flags: option))
            Switcher.shared.feed(KeyInput(kind: .keyUp, keyCode: shortcut.keyCode, flags: option))
            Switcher.shared.feed(KeyInput(kind: .flagsChanged, flags: []))
            // Poll until focus lands (or give up after 400 ms), then tap again like a fast human would.
            func poll() {
                let elapsed = Date().timeIntervalSince(began) * 1000
                if Debug.focusedWindowID() == expected || elapsed > 400 {
                    results.append((Debug.focusedWindowID() == expected, elapsed))
                    let names = Dictionary(windows.map { ($0.id, "\($0.appName):\($0.id)") }, uniquingKeysWith: { a, _ in a })
                    print("  tap \(results.count): expected \(names[expected] ?? "?") got \(Debug.focusedWindowID().flatMap { names[$0] } ?? String(describing: Debug.focusedWindowID())) after \(Int(elapsed)) ms; order now \(WindowManager.shared.currentWindows().prefix(3).map { names[$0.id] ?? "\($0.id)" })")
                    expected = expected == first ? second : first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { tap(remaining - 1) }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.005, execute: poll)
                }
            }
            DispatchQueue.main.async {
                poll()
            }
        }

        func finish() {
            let times = results.map(\.ms).sorted()
            print("GlideTab toggle test: \(results.filter(\.ok).count)/\(results.count) taps landed on the other window")
            print(String(format: "  tap → window in front: median %.0f ms, slowest %.0f ms", times[times.count / 2], times.last ?? 0))
            print(results.allSatisfy(\.ok) ? "PASS" : "FAIL")
            exit(results.allSatisfy(\.ok) ? 0 : 1)
        }

        tap(10)
    }
}
#endif
