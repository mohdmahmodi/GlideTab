import AppKit

func gestureTests() {
    func swipe(_ r: inout GestureRecognizer, fingers: Int, from: Double, to: Double, steps: Int = 20, y: Double = 0.5) -> [GestureOutput] {
        var out: [GestureOutput] = []
        for i in 0...steps {
            let x = from + (to - from) * Double(i) / Double(steps)
            out += r.update((0..<fingers).map { CGPoint(x: x + Double($0) * 0.05, y: y) })
        }
        return out
    }

    test("Gesture: swipe right opens and steps, lifting ends") {
        var r = GestureRecognizer(fingers: 3, trigger: 0.08, step: 0.08)
        let out = swipe(&r, fingers: 3, from: 0.2, to: 0.61)
        check(out.first == .begin(reverse: false), "\(out)")
        check(out.filter { $0 == .step(1) }.count == 4, "\(out)")
        check(r.update([]) == [.end])
        check(r.update([]).isEmpty, "only one end")
    }

    test("Gesture: swipe left reverses; back-and-forth steps both ways") {
        var r = GestureRecognizer(fingers: 3, trigger: 0.08, step: 0.08)
        let out = swipe(&r, fingers: 3, from: 0.6, to: 0.4) + swipe(&r, fingers: 3, from: 0.4, to: 0.6)
        check(out.first == .begin(reverse: true), "\(out)")
        check(out.contains(.step(1)), "\(out)")
    }

    test("Gesture: vertical swipes, wrong finger counts and jitter are ignored") {
        var r = GestureRecognizer(fingers: 3, trigger: 0.08, step: 0.08)
        var out: [GestureOutput] = []
        for i in 0...20 { out += r.update((0..<3).map { CGPoint(x: 0.5 + Double($0) * 0.05, y: 0.2 + Double(i) * 0.03) }) }
        out += r.update([]) // lift
        out += swipe(&r, fingers: 2, from: 0.2, to: 0.8)
        out += swipe(&r, fingers: 4, from: 0.2, to: 0.8)
        _ = r.update([])
        out += swipe(&r, fingers: 3, from: 0.5, to: 0.55)
        check(out.isEmpty, "\(out)")
    }

    test("Gesture: an extra finger mid-swipe ends it") {
        var r = GestureRecognizer(fingers: 3, trigger: 0.08, step: 0.08)
        _ = swipe(&r, fingers: 3, from: 0.2, to: 0.5)
        check(r.update((0..<4).map { CGPoint(x: Double($0) * 0.1, y: 0.5) }) == [.end])
    }

    test("Gesture fuzz: outputs are always well formed") {
        var rng = SeededGenerator(seed: 7)
        var r = GestureRecognizer(fingers: 3, trigger: 0.08, step: 0.08)
        var inGesture = false
        for _ in 0..<200_000 {
            let count = [0, 1, 2, 3, 3, 3, 3, 4].randomElement(using: &rng)!
            let base = Double.random(in: 0...1, using: &rng)
            let touches = (0..<count).map { _ in
                CGPoint(x: base + Double.random(in: -0.02...0.02, using: &rng), y: Double.random(in: 0.4...0.6, using: &rng))
            }
            for output in r.update(touches) {
                switch output {
                case .begin:
                    check(!inGesture, "begin twice")
                    inGesture = true
                case .step: check(inGesture, "step outside a gesture")
                case .end:
                    check(inGesture, "end without begin")
                    inGesture = false
                }
            }
            check(inGesture == r.isActive)
        }
    }
}

func gridTests() {
    test("Grid: everything fits, rows are balanced, for 1…300 items on any screen") {
        let spaces = [CGSize(width: 1100, height: 650), CGSize(width: 1600, height: 900), CGSize(width: 3000, height: 1600),
                      CGSize(width: 500, height: 300), CGSize(width: 260, height: 120)]
        for style in SwitcherStyle.allCases {
            for space in spaces {
                for count in 1...300 {
                    let grid = Grid.fit(count: count, style: style, in: space, gap: 4)
                    check(grid.columns >= 1 && grid.rows >= 1)
                    check(grid.columns * grid.rows >= count, "\(style) \(count): not enough cells")
                    check((grid.rows - 1) * grid.columns < count, "\(style) \(count): an empty row")
                    let size = grid.size(gap: 4)
                    if grid.scale > Grid.minScale {
                        check(size.height <= space.height + 0.5, "\(style) \(count) \(space): too tall \(size)")
                    }
                    check(size.width <= space.width + 0.5 || grid.columns == 1, "\(style) \(count) \(space): too wide \(size)")
                    if style != .list, grid.rows > 1 {
                        let lastRow = count - (grid.rows - 1) * grid.columns
                        check(grid.columns - lastRow < grid.rows, "\(style) \(count): unbalanced, last row \(lastRow) of \(grid.columns)")
                    }
                }
            }
        }
        check(Grid.fit(count: 0, style: .thumbnails, in: CGSize(width: 800, height: 600), gap: 4).rows == 0)
    }
}

func orderingTests() {
    test("MRU order: history decides, even before the window server catches up") {
        // We just switched to 2: history says [2, 1], the window server still stacks 1 in front.
        check(WindowManager.order(history: [2, 1], stacking: [1, 2]) == [2, 1], "a quick second ⌥Tab goes back to 1")
        check(WindowManager.order(history: [], stacking: [5, 6, 7]) == [5, 6, 7], "first run follows stacking")
        check(WindowManager.order(history: [9, 1, 2], stacking: [2, 1]) == [1, 2], "closed windows are dropped")
        check(WindowManager.order(history: [1, 1, 2, 1], stacking: [1, 2]) == [1, 2], "duplicates collapse")
        check(WindowManager.order(history: [1], stacking: [4, 1]) == [1, 4], "new windows join at the end")
    }

    test("Rapid ⌥Tab toggling alternates between the last two windows") {
        var history: [CGWindowID] = [10, 20, 30]
        var landed: [CGWindowID] = []
        for _ in 0..<6 {
            let order = WindowManager.order(history: history, stacking: [30, 20, 10]) // stale stacking on purpose
            let target = order[1]
            landed.append(target)
            history.removeAll { $0 == target }
            history.insert(target, at: 0)
        }
        check(landed == [20, 10, 20, 10, 20, 10], "\(landed)")
    }

    test("MRU order fuzz: always a permutation of the live windows") {
        var rng = SeededGenerator(seed: 3)
        for _ in 0..<20_000 {
            let ids = (0..<Int.random(in: 0...30, using: &rng)).map { _ in CGWindowID.random(in: 1...40, using: &rng) }
            let live = Array(Set(ids)).shuffled(using: &rng)
            let history = (0..<Int.random(in: 0...40, using: &rng)).map { _ in CGWindowID.random(in: 1...50, using: &rng) }
            let order = WindowManager.order(history: history, stacking: live)
            check(order.count == live.count && Set(order) == Set(live), "not a permutation")
        }
    }
}

func searchTests() {
    test("Search: words in any order, case and accent insensitive") {
        check(Search.matches("", in: "anything"))
        check(Search.matches("chrome you", in: "YouTube - Google Chrome"))
        check(Search.matches("CAFE", in: "Café menu"))
        check(!Search.matches("chrome firefox", in: "Google Chrome"))
        check(Search.matches("  spaced  ", in: "spaced out"))
    }
}

func highlightTests() {
    test("Search highlights: every occurrence of every word, merged") {
        let ranges = Search.highlights("japan", in: "Japan itinerary - Japan")
        check(ranges == [NSRange(location: 0, length: 5), NSRange(location: 18, length: 5)], "\(ranges)")
        check(Search.highlights("ita itin", in: "itinerary") == [NSRange(location: 0, length: 4)], "overlaps merge")
        check(Search.highlights("", in: "anything").isEmpty)
        check(Search.highlights("café", in: "CAFE menu") == [NSRange(location: 0, length: 4)], "accent-insensitive")
        check(Search.highlights("zzz", in: "abc").isEmpty)
    }
}

func settingsTests() {
    test("Saved settings with missing fields still decode") {
        let partial = #"[{"id":"7D3E5E8A-3C1B-4C55-9F65-2E1E8E7F0A11","keyCode":48,"modifiers":524288,"apps":"active"}]"#
        let decoded = try? JSONDecoder().decode([ShortcutConfig].self, from: Data(partial.utf8))
        let first = decoded?.first
        check(first?.apps == .active && first?.minimized == .show && first?.screens == .all, "\(String(describing: decoded))")
        let minimal = #"[{"keyCode":50,"modifiers":524288}]"#
        check((try? JSONDecoder().decode([ShortcutConfig].self, from: Data(minimal.utf8)))?.first?.keyCode == 50, "missing id")
        let exceptions = try? JSONDecoder().decode([AppException].self, from: JSONEncoder().encode(AppException.defaults))
        check(exceptions == AppException.defaults)
    }

    test("Minimized / hidden rules: show, hide, or move to the end") {
        let app = NSRunningApplication.current
        let a = WindowInfo(id: 1, app: app, title: "a", ax: nil, isMinimized: true, isOnOtherSpace: false)
        let b = WindowInfo(id: 2, app: app, title: "b", ax: nil, isMinimized: false, isOnOtherSpace: false)
        let c = WindowInfo(id: 3, app: app, title: "c", ax: nil, isMinimized: false, isOnOtherSpace: false)
        var shortcut = ShortcutConfig.defaults[0]
        check(shortcut.arrange([a, b, c]).map(\.id) == [1, 2, 3])
        shortcut.minimized = .atEnd
        check(shortcut.arrange([a, b, c]).map(\.id) == [2, 3, 1])
        shortcut.minimized = .hide
        check(shortcut.arrange([a, b, c]).map(\.id) == [2, 3])
    }

    test("Window titles in each title style") {
        let app = NSRunningApplication.current
        let name = app.localizedName ?? ""
        let titled = SwitcherItem.window(WindowInfo(id: 1, app: app, title: "Doc", ax: nil, isMinimized: false, isOnOtherSpace: false))
        let untitled = SwitcherItem.window(WindowInfo(id: 2, app: app, title: "", ax: nil, isMinimized: false, isOnOtherSpace: false))
        check(titled.title(.window) == "Doc" && titled.title(.app) == name && titled.title(.appAndWindow) == "\(name) – Doc")
        check(untitled.title(.window) == name && untitled.title(.appAndWindow) == name)
    }

    test("Subtitles never repeat the title") {
        let app = NSRunningApplication.current
        let name = app.localizedName ?? ""
        let titled = SwitcherItem.window(WindowInfo(id: 1, app: app, title: "Doc", ax: nil, isMinimized: false, isOnOtherSpace: false))
        check(titled.subtitle(.window) == name && titled.subtitle(.app) == "Doc" && titled.subtitle(.appAndWindow).isEmpty)
        let untitled = SwitcherItem.window(WindowInfo(id: 2, app: app, title: "", ax: nil, isMinimized: false, isOnOtherSpace: false))
        check(TitleStyle.allCases.allSatisfy { untitled.subtitle($0).isEmpty })
    }
}

func browserTests() {
    test("Chromium tab list parsing (incl. missing values and ragged lists)") {
        let value: [Any] = [
            [Double(11), Double(12)],
            ["Inbox", "Docs"],
            [[0.0, 25.0, 1200.0, 825.0], [100.0, 100.0, 900.0, 700.0]],
            [Double(2), Double(1)],
            [["Mail", "Inbox"], ["Docs"]],
            [["https://mail.example.com", NSNull()], ["https://docs.example.com/x"]],
            [[Double(501), Double(502)], [Double(601)]],
        ]
        let windows = BrowserTabs.parseChromium(value)
        check(windows.count == 2)
        check(windows[0].scriptID == "11" && windows[0].activeIndex == 2 && windows[0].tabs.count == 2)
        check(windows[0].bounds == CGRect(x: 0, y: 25, width: 1200, height: 800), "\(String(describing: windows[0].bounds))")
        check(windows[0].tabs[1].url == "", "missing URL becomes empty")
        check(windows[0].tabs[0].tabID == "501")
        let textIDs = BrowserTabs.parseChromium([["548127963"], ["A"], [[0.0, 0.0, 10.0, 10.0]], [Double(1)], [["A"]], [["u"]], [["99"]]])
        check(textIDs.first?.scriptID == "548127963" && textIDs.first?.tabs.first?.tabID == "99", "Chrome sends ids as text")
        check(BrowserTabs.parseChromium([1, 2, 3]).isEmpty, "garbage in, nothing out")
        check(BrowserTabs.parseChromium([[Double(1)], [], [], [], [], [], []]).isEmpty, "ragged lists don't crash")
    }

    test("Safari tab list parsing") {
        let value: [Any] = [
            [Double(3), Double(4)],
            ["Apple", "Settings"],
            [[0.0, 0.0, 800.0, 600.0], [0.0, 0.0, 400.0, 300.0]],
            [["Apple", "Swift"], []],
            [["https://apple.com", "https://swift.org"], []],
            [[false, true], []],
        ]
        let windows = BrowserTabs.parseSafari(value)
        check(windows.count == 1, "tab-less windows (Settings) are skipped")
        check(windows.first?.activeIndex == 2)
    }

    test("Apple event descriptor decoding") {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: "a"), at: 1)
        list.insert(NSAppleEventDescriptor(int32: 7), at: 2)
        list.insert(NSAppleEventDescriptor(boolean: true), at: 3)
        list.insert(NSAppleEventDescriptor.null(), at: 4)
        list.insert(NSAppleEventDescriptor.list(), at: 5)
        let value = BrowserTabs.value(of: list) as? [Any]
        check(value?.count == 5)
        check(value?[0] as? String == "a")
        check(value?[1] as? Double == 7)
        check(value?[2] as? Bool == true)
        check(value?[3] is NSNull)
        check((value?[4] as? [Any])?.isEmpty == true)
    }

    test("Matching browser windows to real windows") {
        let candidates: [(frame: CGRect, title: String)] = [
            (CGRect(x: 0, y: 25, width: 1200, height: 800), "Inbox - Google Chrome - Work"),
            (CGRect(x: 0, y: 25, width: 1200, height: 800), "Docs - Google Chrome - Personal"),
            (CGRect(x: 50, y: 50, width: 700, height: 500), "News - Google Chrome"),
        ]
        check(BrowserTabs.matchIndex(name: "News", bounds: CGRect(x: 51, y: 49, width: 700, height: 501), candidates: candidates) == 2, "by frame")
        let frame = CGRect(x: 0, y: 25, width: 1200, height: 800)
        check(BrowserTabs.matchIndex(name: "Docs", bounds: frame, candidates: candidates) == 1, "same frame, by title")
        check(BrowserTabs.matchIndex(name: "Inbox", bounds: nil, candidates: candidates) == 0, "by title alone")
        check(BrowserTabs.matchIndex(name: "Nope", bounds: CGRect(x: 0, y: 25, width: 1200, height: 800), candidates: candidates) == nil, "ambiguous")
        check(BrowserTabs.matchIndex(name: "", bounds: nil, candidates: candidates) == nil)
    }

    test("Chrome profile names from window titles") {
        check(BrowserTabs.profile(fromTitle: "YouTube - Google Chrome - Personal", appName: "Google Chrome") == "Personal")
        check(BrowserTabs.profile(fromTitle: "A - B - Google Chrome - Work Stuff", appName: "Google Chrome") == "Work Stuff")
        check(BrowserTabs.profile(fromTitle: "YouTube - Google Chrome", appName: "Google Chrome") == nil)
        check(BrowserTabs.profile(fromTitle: "Untitled", appName: "") == nil)
    }
}

func miscTests() {
    test("Version comparison for updates") {
        check(Updater.isNewer("1.10", than: "1.9"))
        check(Updater.isNewer("2", than: "1.9.9"))
        check(!Updater.isNewer("1.1", than: "1.1.0"))
        check(!Updater.isNewer("1.0", than: "1.1"))
        check(Updater.isNewer("1.1.1", than: "1.1"))
        check(!Updater.isNewer("garbage", than: "1.0"))
    }

    test("Shortcut model: matching, display, encoding, ⌘Tab detection") {
        let optionTab = ShortcutConfig.defaults[0]
        check(optionTab.matches(keyCode: KeyCode.tab, flags: [.maskAlternate]))
        check(optionTab.matches(keyCode: KeyCode.tab, flags: [.maskAlternate, .maskShift]), "⇧ allowed (reverse)")
        check(!optionTab.matches(keyCode: KeyCode.tab, flags: [.maskAlternate, .maskCommand]))
        check(optionTab.matches(keyCode: KeyCode.tab, flags: [.maskAlternate, .maskSecondaryFn, .maskNumericPad]), "Fn / keypad flags ignored")
        check(optionTab.displayString == "⌥⇥", optionTab.displayString)
        let commandTab = ShortcutConfig(keyCode: KeyCode.tab, modifiers: CGEventFlags.maskCommand.rawValue)
        check(commandTab.isCommandTab && !optionTab.isCommandTab)
        let all = CGEventFlags([.maskControl, .maskAlternate, .maskShift, .maskCommand]).rawValue
        check(ShortcutConfig(keyCode: KeyCode.tab, modifiers: all).displayString == "⌃⌥⇧⌘⇥")
        let data = try? JSONEncoder().encode(ShortcutConfig.defaults)
        let decoded = data.flatMap { try? JSONDecoder().decode([ShortcutConfig].self, from: $0) }
        check(decoded == ShortcutConfig.defaults, "round trip")
        check(!KeyNames.name(for: 0).isEmpty)
    }

    test("Tab search covers title, site and profile") {
        let tab = BrowserTab(app: NSRunningApplication.current, title: "Pull requests", url: "https://www.github.com/x",
                             handle: .script(windowID: "1", index: 2, tabID: nil))
        tab.profile = "Work"
        let item = SwitcherItem.tab(tab)
        check(tab.host == "github.com")
        check(item.matches("github pull"))
        check(item.matches("work"))
        check(!item.matches("gitlab"))
        check(item.actions == [.close])
        check(item.subtitle() == "Work · github.com", item.subtitle())
    }
}
