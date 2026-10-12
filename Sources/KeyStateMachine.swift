import CoreGraphics

/// What the keyboard asks the switcher to do. Executed in order on the main queue.
enum SwitcherIntent: Equatable {
    case begin(session: Int, shortcut: Int, reverse: Bool)
    case move(Int)
    case moveRow(Int)
    case commit(session: Int)
    case cancel(session: Int)
    case type(Character)
    case deleteBackward
    case clearSearch
}

struct KeyInput {
    enum Kind { case keyDown, keyUp, flagsChanged }
    var kind: Kind
    var keyCode: Int64 = 0
    var flags: CGEventFlags = []
    /// The printable character the key produces, if any.
    var character: Character? = nil
}

/// The switcher's keyboard logic, with no UI or system calls so it can be tested exhaustively. It runs
/// synchronously in the event tap; per-session ids make a late `end(session:)` from an old session harmless.
struct KeyStateMachine {
    var shortcuts: [ShortcutConfig]
    /// Releasing the modifiers leaves the switcher open (Return switches).
    var keepOpen = false

    private(set) var session = 0
    /// The shortcut holding the current session open, or nil if it was opened another way (gesture, CLI).
    private(set) var activeShortcut: Int?
    /// Copied from that shortcut when the session starts, so changing settings mid-session can't strand it.
    private var activeHold: CGEventFlags = []
    private var activeKey: Int64 = KeyCode.tab
    private var activeHasShift = false
    private(set) var isActive = false
    /// Releasing the modifiers no longer switches (keep-open, typing a search, or gesture/CLI sessions).
    private(set) var isPinned = false
    /// Key-downs we swallowed, so their key-ups are swallowed too.
    private(set) var swallowed: Set<Int64> = []
    /// Characters in the search, so Esc can clear a search before it closes the switcher (like Spotlight).
    private(set) var queryLength = 0

    init(shortcuts: [ShortcutConfig]) {
        self.shortcuts = shortcuts
    }

    /// Returns whether to swallow the event, and what the switcher should do.
    mutating func handle(_ input: KeyInput) -> (swallow: Bool, intents: [SwitcherIntent]) {
        switch input.kind {
        case .flagsChanged:
            guard isActive, !isPinned, activeShortcut != nil, !input.flags.contains(activeHold) else { return (false, []) }
            let ended = session
            reset()
            return (false, [.commit(session: ended)])

        case .keyUp:
            return (swallowed.remove(input.keyCode) != nil, [])

        case .keyDown:
            guard isActive else { return startIfShortcut(input) }
            swallowed.insert(input.keyCode)
            return (true, intentsWhileActive(input))
        }
    }

    /// Starts a session not driven by held modifiers (trackpad gesture, command line).
    mutating func startExternal() -> Int {
        session += 1
        isActive = true
        isPinned = true
        queryLength = 0
        activeShortcut = nil
        activeKey = KeyCode.tab
        activeHasShift = false
        return session
    }

    /// The switcher closed `session` on its own (click, action, …).
    mutating func end(session ended: Int) {
        if ended == session { reset() }
    }

    /// The search field was clicked: keep the switcher open after the keys are released, as when typing.
    mutating func pin() {
        if isActive { isPinned = true }
    }

    /// The search was cleared with the field's clear button.
    mutating func clearQuery() {
        queryLength = 0
    }

    private mutating func reset() {
        isActive = false
        isPinned = false
        activeShortcut = nil
        queryLength = 0
    }

    private mutating func startIfShortcut(_ input: KeyInput) -> (swallow: Bool, intents: [SwitcherIntent]) {
        // A key we let through can't have a pending swallowed key-up any more.
        swallowed.remove(input.keyCode)
        guard let index = shortcuts.firstIndex(where: { $0.isValid && $0.matches(keyCode: input.keyCode, flags: input.flags) })
        else { return (false, []) }
        session += 1
        isActive = true
        isPinned = keepOpen
        queryLength = 0
        activeShortcut = index
        activeHold = shortcuts[index].holdFlags
        activeKey = shortcuts[index].keyCode
        activeHasShift = shortcuts[index].flags.contains(.maskShift)
        swallowed.insert(input.keyCode)
        let reverse = input.flags.contains(.maskShift) && !shortcuts[index].flags.contains(.maskShift)
        return (true, [.begin(session: session, shortcut: index, reverse: reverse)])
    }

    private mutating func intentsWhileActive(_ input: KeyInput) -> [SwitcherIntent] {
        let shift = input.flags.contains(.maskShift)
        let cycleKey = activeKey
        let shortcutHasShift = activeHasShift

        switch input.keyCode {
        case KeyCode.escape:
            // First Esc clears a search, the next one closes.
            if queryLength > 0 {
                queryLength = 0
                return [.clearSearch]
            }
            let ended = session
            reset()
            return [.cancel(session: ended)]
        case KeyCode.returnKey, KeyCode.enter:
            let ended = session
            reset()
            return [.commit(session: ended)]
        case cycleKey, KeyCode.tab:
            return [.move(shift && !shortcutHasShift ? -1 : 1)]
        case KeyCode.left: return [.move(-1)]
        case KeyCode.right: return [.move(1)]
        case KeyCode.up: return [.moveRow(-1)]
        case KeyCode.down: return [.moveRow(1)]
        case KeyCode.delete:
            queryLength = max(0, queryLength - 1)
            return [.deleteBackward]
        default:
            // Space only counts once a search has started, so it can separate words.
            guard let character = input.character, character != " " || isPinned else { return [] }
            isPinned = true
            queryLength += 1
            return [.type(character)]
        }
    }
}
