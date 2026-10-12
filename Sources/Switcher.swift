import AppKit

/// Owns the global shortcuts and the current switching session. Keys are decided synchronously on the input
/// thread by `KeyStateMachine` (under `inputLock`); the resulting intents run in order on the main queue.
final class Switcher {
    static let shared = Switcher()

    private lazy var keyTap: EventTap = {
        let tap = EventTap(events: [.keyDown, .keyUp, .flagsChanged]) { [unowned self] type, event in
            self.handleKey(type, event)
        }
        tap.onReenabled = { [unowned self] in self.resyncModifiers() }
        return tap
    }()
    private lazy var trackpad = TrackpadMonitor { [weak self] output in
        DispatchQueue.main.async { self?.handleGesture(output) }
    }
    private let panel = SwitcherPanel()
    private let preview = PreviewWindow()
    #if DEBUG
    /// Stress tests: run everything except actually focusing a window.
    var isDryRun = false
    #else
    private let isDryRun = false
    #endif

    /// State shared with the input thread. Only touch it through `withInput`.
    private struct InputState {
        var keys: KeyStateMachine
        var recorder: ((ShortcutConfig?) -> Void)?
        /// The frontmost app wants our shortcuts for itself (an exception).
        var frontmostIgnoresShortcuts = false
        var appIsActive = false
    }
    private let inputLock = NSLock()
    private var input = InputState(keys: KeyStateMachine(shortcuts: Prefs.shortcuts))

    private func withInput<T>(_ body: (inout InputState) -> T) -> T {
        inputLock.lock()
        defer { inputLock.unlock() }
        return body(&input)
    }

    // The open session, if any (main thread).
    private var openSession: Int?
    private var gestureSession: Int?
    private var screen: NSScreen?
    /// Items shown with no search; plus background tabs that only appear when searching.
    private var baseItems: [SwitcherItem] = []
    private var searchOnlyItems: [SwitcherItem] = []
    private var items: [SwitcherItem] = []
    private var selected = 0
    private var query = ""
    private var isShown = false
    private var clickMonitor: Any?
    private var sessionWindows: [WindowInfo] = []
    private var refreshedTabs = false
    private var ignoringApps: Set<String> = []
    private var tapRunning = false
    /// Bumped on every commit, so a slow browser tab switch can't steal focus after a newer switch.
    private var commitGeneration = 0

    private init() {
        panel.onHover = { [weak self] in self?.select($0) }
        panel.onClick = { [weak self] in
            self?.select($0)
            self?.commit()
        }
        panel.onAction = { [weak self] in self?.perform($1, on: $0) }
        // Clicking the search field means "I want to type": keep the switcher open when the keys are let go.
        panel.onSearchClick = { [weak self] in
            self?.withInput { $0.keys.pin() }
            self?.panel.setSearchFocused(true)
        }
        panel.onSearchClear = { [weak self] in
            self?.withInput { $0.keys.clearQuery() }
            self?.search("")
        }
    }

    func start() -> Bool {
        guard keyTap.start() else { return false }
        tapRunning = true
        // Only now that our shortcut works may the system ⌘Tab be turned off.
        Prefs.applyNativeCommandTab()
        applySettings()
        let center = NotificationCenter.default
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.updateFrontmost() }
        center.addObserver(forName: .shortcutsChanged, object: nil, queue: .main) { [weak self] _ in self?.applySettings() }
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.applySettings() }
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.withInput { $0.appIsActive = true }
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.withInput { $0.appIsActive = false }
            // Recording only makes sense while Settings is in front; otherwise it would capture other apps' keys.
            self?.cancelRecording(notify: true)
        }
        // A display came or went: the open switcher may now be off screen.
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.close()
        }
        return true
    }

    private func applySettings() {
        let shortcuts = Prefs.shortcuts
        let (changed, recording) = withInput { state -> (Bool, Bool) in
            let changed = state.keys.shortcuts != shortcuts
            state.keys.shortcuts = shortcuts
            state.keys.keepOpen = Prefs.keepOpen
            return (changed, state.recorder != nil)
        }
        if changed && !recording && tapRunning { Prefs.applyNativeCommandTab() }
        trackpad.configure(fingers: Prefs.gesture.count)
        let ignoring = Prefs.shortcutIgnoringApps
        if ignoring != ignoringApps {
            ignoringApps = ignoring
            updateFrontmost()
        }
    }

    private func updateFrontmost() {
        let ignores = NSWorkspace.shared.frontmostApplication?.bundleIdentifier.map(ignoringApps.contains) ?? false
        withInput { $0.frontmostIgnoresShortcuts = ignores }
    }

    // MARK: Input (input thread)

    private func handleKey(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let kind: KeyInput.Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let (recording, appIsActive, ignores, active) = withInput {
            ($0.recorder != nil, $0.appIsActive, $0.frontmostIgnoresShortcuts, $0.keys.isActive)
        }
        if recording && kind != .flagsChanged {
            guard appIsActive else { return false } // recording ends when Settings isn't in front
            if kind == .keyDown { record(keyCode: keyCode, flags: event.flags) }
            return true
        }
        // Remote desktops and virtual machines can keep the shortcuts for themselves.
        if ignores && !active && kind == .keyDown { return false }
        var input = KeyInput(kind: kind, keyCode: keyCode, flags: event.flags)
        // Only decode characters while switching: no work for ordinary typing.
        if kind == .keyDown && active { input.character = Self.typedCharacter(event) }
        return feed(input)
    }

    /// Runs one key through the state machine. Also the entry point for the stress tests.
    @discardableResult
    func feed(_ input: KeyInput) -> Bool {
        let (swallow, intents) = withInput { $0.keys.handle(input) }
        if !intents.isEmpty {
            DispatchQueue.main.async { intents.forEach(self.perform) }
        }
        return swallow
    }

    /// After macOS disabled our tap, key events were missed, possibly the release of the held modifier.
    /// Look at the modifiers as they are now, so a session can't stay open waiting for a release it missed.
    private func resyncModifiers() {
        feed(KeyInput(kind: .flagsChanged, flags: CGEventSource.flagsState(.combinedSessionState)))
    }

    /// The character a key types, ignoring held ⌘ ⌥ ⌃ (so ⌥A searches for "a", not "å"). Read from the raw
    /// event on the input thread: converting to NSEvent there isn't safe.
    private static func typedCharacter(_ event: CGEvent) -> Character? {
        guard let plain = event.copy() else { return nil }
        plain.flags = event.flags.intersection([.maskShift, .maskAlphaShift])
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        plain.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        guard length > 0, let character = String(utf16CodeUnits: chars, count: length).lowercased().first,
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol || character == " "
        else { return nil }
        return character
    }

    // MARK: Intents (main thread)

    private func handleGesture(_ output: GestureOutput) {
        switch output {
        case let .begin(reverse):
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            if withInput({ $0.keys.isActive }) {
                move(reverse ? -1 : 1, wrap: true)
            } else {
                let session = withInput { $0.keys.startExternal() }
                gestureSession = session
                begin(session: session, shortcut: nil, reverse: reverse)
            }
        case let .step(direction):
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            move(direction, wrap: true)
        case .end:
            guard let session = gestureSession else { return }
            gestureSession = nil
            if !Prefs.keepOpen && session == openSession { commit() }
        }
    }

    private func perform(_ intent: SwitcherIntent) {
        switch intent {
        case let .begin(session, index, reverse):
            // A begin that was overtaken (e.g. the command line opened a newer session) is dropped.
            let shortcut = withInput { state -> ShortcutConfig?? in
                guard session == state.keys.session else { return .none }
                return .some(state.keys.shortcuts.indices.contains(index) ? state.keys.shortcuts[index] : nil)
            }
            guard let shortcut else { return }
            begin(session: session, shortcut: shortcut, reverse: reverse)
        case let .move(delta): move(delta, wrap: true)
        case let .moveRow(delta): move(delta * panel.columns, wrap: false)
        case let .commit(session): if session == openSession { commit() }
        case let .cancel(session): if session == openSession { close() }
        case let .type(character): search(query + String(character))
        case .deleteBackward: search(String(query.dropLast()))
        case .clearSearch: search("")
        }
    }

    // MARK: Shortcut recording (Settings)

    /// Captures the next key combination (including ⌘Tab) while Settings is in front.
    /// Calls back with nil if cancelled (Esc, or Settings leaving the front).
    func recordShortcut(_ completion: @escaping (ShortcutConfig?) -> Void) {
        withInput {
            $0.recorder = completion
            $0.appIsActive = NSApp.isActive
        }
        Private.setNativeCommandTab(enabled: false)
    }

    func cancelRecording(notify: Bool = false) {
        let recorder = withInput { state -> ((ShortcutConfig?) -> Void)? in
            defer { state.recorder = nil }
            return state.recorder
        }
        guard recorder != nil else { return }
        Prefs.applyNativeCommandTab()
        if notify { recorder?(nil) }
    }

    /// Input thread.
    private func record(keyCode: Int64, flags: CGEventFlags) {
        let modifiers = flags.intersection(ShortcutConfig.recordable)
        let shortcut = ShortcutConfig(keyCode: keyCode, modifiers: modifiers.rawValue)
        let cancel = keyCode == KeyCode.escape && modifiers.isEmpty
        guard cancel || shortcut.isValid else {
            DispatchQueue.main.async { NSSound.beep() }
            return
        }
        let recorder = withInput { state -> ((ShortcutConfig?) -> Void)? in
            defer { state.recorder = nil }
            return state.recorder
        }
        DispatchQueue.main.async {
            Prefs.applyNativeCommandTab()
            recorder?(cancel ? nil : shortcut)
        }
    }

    // MARK: Session

    /// Opens the switcher without a shortcut held (command line). It stays open until a choice or Esc.
    func showPinned() {
        let session = withInput { $0.keys.startExternal() }
        begin(session: session, shortcut: nil, reverse: false)
    }

    private func begin(session: Int, shortcut: ShortcutConfig?, reverse: Bool) {
        if openSession != nil { close() }
        openSession = session
        var windows = WindowManager.shared.currentWindows().filter(Prefs.includes)
        // No screens for a moment (waking, displays reconfiguring): don't open, and release the keyboard.
        guard let screen = Self.screen(for: Prefs.showOn, frontWindow: windows.first) else { return close() }
        self.screen = screen
        if let shortcut {
            if shortcut.apps == .active, let front = NSWorkspace.shared.frontmostApplication {
                windows = windows.filter { $0.pid == front.processIdentifier }
            }
            if shortcut.spaces == .current { windows = windows.filter { !$0.isOnOtherSpace } }
            if shortcut.screens == .current { windows = windows.filter { $0.isOn(screen) } }
            windows = shortcut.arrange(windows)
        }
        baseItems = windows.map(SwitcherItem.window)
        searchOnlyItems = []
        addTabs(for: windows)
        items = baseItems
        query = ""
        selected = items.count > 1 ? (reverse ? items.count - 1 : 1) : 0

        sessionWindows = windows
        // A quick tap switches straight to the previous window without flashing the UI in between.
        let delay = shortcut == nil || withInput({ $0.keys.isPinned }) ? 0 : 0.16
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.openSession == session, !self.isShown else { return }
            self.render()
        }
    }

    private static func screen(for choice: ShowOn, frontWindow: WindowInfo?) -> NSScreen? {
        guard let fallback = NSScreen.main ?? NSScreen.screens.first else { return nil }
        switch choice {
        case .mouse:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? fallback
        case .active:
            return frontWindow.flatMap { window in NSScreen.screens.first { window.isOn($0) } } ?? fallback
        case .main:
            return NSScreen.screens.first ?? fallback
        }
    }

    private func addTabs(for windows: [WindowInfo]) {
        let mode = Prefs.browserTabs
        guard mode != .off else { return }
        let tabs = BrowserTabs.shared.backgroundTabs(in: windows).map(SwitcherItem.tab)
        baseItems.removeAll(where: \.isTab)
        if mode == .always { baseItems += tabs } else { searchOnlyItems = tabs }
    }

    private func render() {
        guard let session = openSession else { return }
        if !isShown && Prefs.browserTabs == .always { refreshTabs() }
        if !isShown {
            // Capture only once the panel is visible: a quick ⌥Tab costs nothing and doesn't flicker protected video.
            Thumbnails.shared.capture(baseItems.compactMap(\.window)) { [weak self] id, image in
                guard let self, self.openSession == session else { return }
                self.panel.update(id: id, image: image)
            }
        }
        let total = baseItems.count + (query.isEmpty ? 0 : searchOnlyItems.count)
        guard let screen else { return close() }
        panel.present(items, selected: selected, query: query, total: total, style: Prefs.style, on: screen)
        isShown = true
        updatePreview()
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.close()
            }
        }
    }

    private func move(_ delta: Int, wrap: Bool) {
        guard openSession != nil, !items.isEmpty else { return }
        let target = selected + delta
        if wrap {
            select((target % items.count + items.count) % items.count)
        } else if items.indices.contains(target) {
            select(target)
        }
    }

    private func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selected = index
        panel.select(index)
        updatePreview()
    }

    private func updatePreview() {
        guard isShown, Prefs.preview, items.indices.contains(selected), case let .window(window) = items[selected] else {
            return preview.hide()
        }
        preview.show(window)
    }

    /// Fetches fresh tabs once per session, only when tabs are about to show, so a quick ⌥Tab never keeps a
    /// browser busy just as you switch to it. Cached tabs show meanwhile.
    private func refreshTabs() {
        guard let session = openSession, !refreshedTabs, Prefs.browserTabs != .off else { return }
        refreshedTabs = true
        let windows = sessionWindows
        BrowserTabs.shared.refresh(Array(Set(windows.map(\.app)))) { [weak self] in
            guard let self, self.openSession == session else { return }
            self.addTabs(for: windows)
            self.applyQuery(keepSelection: true)
        }
    }

    private func search(_ text: String) {
        guard openSession != nil else { return }
        if !text.isEmpty { refreshTabs() }
        query = text
        applyQuery(keepSelection: false)
    }

    /// Recomputes the visible items for the current query.
    private func applyQuery(keepSelection: Bool) {
        let current = items.indices.contains(selected) ? items[selected] : nil
        let pool = query.isEmpty ? baseItems : baseItems + searchOnlyItems
        items = pool.filter { $0.matches(query) }
        if keepSelection, let current, let index = items.firstIndex(where: { $0.isSame(as: current) }) {
            selected = index
        } else {
            selected = keepSelection ? min(selected, max(items.count - 1, 0)) : 0
        }
        if isShown { render() }
    }

    private func perform(_ action: WindowAction, on index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        switch (action, item) {
        case let (.close, .window(window)):
            WindowManager.shared.close(window)
            remove(item)
        case let (.close, .tab(tab)):
            BrowserTabs.shared.close(tab)
            remove(item)
        case let (.minimize, .window(window)):
            WindowManager.shared.minimize(window)
            window.isMinimized = true
            render()
        case let (.fullScreen, .window(window)):
            close()
            WindowManager.shared.focus(window, fullScreen: true)
        default:
            break
        }
    }

    private func remove(_ item: SwitcherItem) {
        baseItems.removeAll { $0.isSame(as: item) }
        searchOnlyItems.removeAll { $0.isSame(as: item) }
        items.removeAll { $0.isSame(as: item) }
        guard !items.isEmpty || !query.isEmpty else { return close() }
        selected = min(selected, max(items.count - 1, 0))
        render()
    }

    private func commit() {
        guard openSession != nil else { return }
        let target = items.indices.contains(selected) ? items[selected] : nil
        // If the full-size preview already shows the chosen window, leave it up until the real window is in front,
        // so there's no flash of whatever was behind it.
        let handOff = target?.thumbnailID.map { $0 == preview.shownWindowID } ?? false
        let previewToken = preview.token
        close(keepPreview: handOff && !isDryRun)
        guard !isDryRun else { return }
        commitGeneration += 1
        let generation = commitGeneration
        switch target {
        case let .window(window):
            WindowManager.shared.focus(window) { [preview] in if handOff { preview.fadeOut(ifStill: previewToken) } }
        case let .tab(tab):
            BrowserTabs.shared.select(tab) { [weak self] in
                // The browser answered late and you've switched elsewhere since: don't jump back.
                guard self?.commitGeneration == generation else { return }
                if let window = tab.window { WindowManager.shared.focus(window) } else { tab.app.activate() }
            }
        case nil:
            break
        }
    }

    private func close(keepPreview: Bool = false) {
        if let openSession { withInput { $0.keys.end(session: openSession) } }
        openSession = nil
        gestureSession = nil
        isShown = false
        panel.reset()
        if !keepPreview { preview.hide() }
        baseItems = []
        searchOnlyItems = []
        items = []
        sessionWindows = []
        refreshedTabs = false
        query = ""
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    #if DEBUG
    // MARK: Introspection (stress tests)

    struct State: Equatable {
        var isOpen: Bool
        var isShown: Bool
        var itemCount: Int
        var selected: Int
        var keyboardActive: Bool
    }

    var state: State {
        State(isOpen: openSession != nil, isShown: isShown, itemCount: items.count, selected: selected,
              keyboardActive: withInput { $0.keys.isActive })
    }
    #endif
}
