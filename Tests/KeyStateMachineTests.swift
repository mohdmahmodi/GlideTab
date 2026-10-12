import CoreGraphics
import Foundation

private let option = CGEventFlags.maskAlternate
private let command = CGEventFlags.maskCommand
private let shift = CGEventFlags.maskShift

private func down(_ key: Int64, _ flags: CGEventFlags = [], _ character: Character? = nil) -> KeyInput {
    KeyInput(kind: .keyDown, keyCode: key, flags: flags, character: character)
}
private func up(_ key: Int64, _ flags: CGEventFlags = []) -> KeyInput { KeyInput(kind: .keyUp, keyCode: key, flags: flags) }
private func flags(_ flags: CGEventFlags) -> KeyInput { KeyInput(kind: .flagsChanged, flags: flags) }

private func machine(_ shortcuts: [ShortcutConfig] = ShortcutConfig.defaults, keepOpen: Bool = false) -> KeyStateMachine {
    var m = KeyStateMachine(shortcuts: shortcuts)
    m.keepOpen = keepOpen
    return m
}

func keyStateMachineTests() {
    test("⌥Tab opens, releasing ⌥ switches") {
        var m = machine()
        check(m.handle(flags(option)).intents.isEmpty, "pressing ⌥ alone does nothing")
        let (swallow, intents) = m.handle(down(KeyCode.tab, option))
        check(swallow, "trigger swallowed")
        check(intents == [.begin(session: 1, shortcut: 0, reverse: false)], "\(intents)")
        check(m.isActive)
        check(m.handle(up(KeyCode.tab, option)).swallow, "its key-up swallowed")
        let release = m.handle(flags([]))
        check(!release.swallow, "modifier changes always pass through")
        check(release.intents == [.commit(session: 1)], "\(release.intents)")
        check(!m.isActive)
    }

    test("⇧⌥Tab opens in reverse; Tab / ⇧Tab / arrows move") {
        var m = machine()
        check(m.handle(down(KeyCode.tab, option.union(shift))).intents == [.begin(session: 1, shortcut: 0, reverse: true)])
        check(m.handle(down(KeyCode.tab, option)).intents == [.move(1)])
        check(m.handle(down(KeyCode.tab, option.union(shift))).intents == [.move(-1)])
        check(m.handle(down(KeyCode.left, option)).intents == [.move(-1)])
        check(m.handle(down(KeyCode.right, option)).intents == [.move(1)])
        check(m.handle(down(KeyCode.up, option)).intents == [.moveRow(-1)])
        check(m.handle(down(KeyCode.down, option)).intents == [.moveRow(1)])
    }

    test("Other keys pass through when idle") {
        var m = machine()
        check(!m.handle(down(KeyCode.tab)).swallow, "plain Tab")
        check(!m.handle(down(KeyCode.tab, command)).swallow, "⌘Tab with an ⌥ shortcut")
        check(!m.handle(down(KeyCode.tab, option.union(command))).swallow, "extra modifier")
        check(!m.handle(down(KeyCode.tab, option.union(.maskControl))).swallow, "extra ⌃")
        check(!m.handle(down(12, option)).swallow, "⌥Q")
        check(!m.handle(up(KeyCode.tab)).swallow)
        check(!m.isActive)
    }

    test("Esc cancels, Return switches") {
        var m = machine()
        _ = m.handle(down(KeyCode.tab, option))
        check(m.handle(down(KeyCode.escape, option)).intents == [.cancel(session: 1)])
        check(!m.isActive)
        check(m.handle(flags([])).intents.isEmpty, "release after cancel does nothing")
        _ = m.handle(down(KeyCode.tab, option))
        check(m.handle(down(KeyCode.returnKey, option)).intents == [.commit(session: 2)])
        check(!m.isActive)
    }

    test("Typing searches and pins the switcher open") {
        var m = machine()
        _ = m.handle(down(KeyCode.tab, option))
        check(m.handle(down(49, option, " ")).intents.isEmpty, "space before typing is ignored")
        check(m.handle(down(0, option, "a")).intents == [.type("a")])
        check(m.isPinned)
        check(m.handle(down(49, option, " ")).intents == [.type(" ")], "space once searching")
        check(m.handle(down(KeyCode.delete, option)).intents == [.deleteBackward])
        check(m.handle(flags([])).intents.isEmpty, "release no longer switches")
        check(m.queryLength == 1, "\(m.queryLength)")
        check(m.isActive)
        check(m.handle(down(KeyCode.tab)).intents == [.move(1)], "Tab still moves without ⌥")
        check(m.handle(down(KeyCode.returnKey)).intents == [.commit(session: 1)])
        check(!m.isActive && !m.isPinned)
    }

    test("Esc clears a search first, then closes (like Spotlight)") {
        var m = machine()
        _ = m.handle(down(KeyCode.tab, option))
        _ = m.handle(down(0, option, "a"))
        _ = m.handle(down(1, option, "s"))
        check(m.handle(down(KeyCode.escape)).intents == [.clearSearch], "first Esc clears")
        check(m.isActive && m.isPinned, "still open")
        check(m.handle(down(KeyCode.escape)).intents == [.cancel(session: 1)], "second Esc closes")
        check(!m.isActive)
        _ = m.handle(down(KeyCode.tab, option))
        _ = m.handle(down(0, option, "a"))
        _ = m.handle(down(KeyCode.delete, option))
        check(m.handle(down(KeyCode.escape)).intents == [.cancel(session: 2)], "nothing left to clear")
    }

    test("Clicking the search field pins the switcher open") {
        var m = machine()
        _ = m.handle(down(KeyCode.tab, option))
        m.pin()
        check(m.handle(flags([])).intents.isEmpty, "release no longer switches")
        check(m.handle(down(KeyCode.returnKey)).intents == [.commit(session: 1)])
        var idle = machine()
        idle.pin()
        check(!idle.isPinned, "pinning does nothing when closed")
    }

    test("Keep-open mode") {
        var m = machine(keepOpen: true)
        _ = m.handle(down(KeyCode.tab, option))
        check(m.handle(flags([])).intents.isEmpty)
        check(m.isActive)
        check(m.handle(down(KeyCode.escape)).intents == [.cancel(session: 1)])
    }

    test("A late end of an old session can't cancel a newer one") {
        var m = machine()
        _ = m.handle(down(KeyCode.tab, option))
        _ = m.handle(flags([])) // commit(1) queued
        _ = m.handle(down(KeyCode.tab, option)) // session 2 starts before the switcher ran commit(1)
        m.end(session: 1)
        check(m.isActive, "session 2 survives")
        check(m.handle(flags([])).intents == [.commit(session: 2)])
    }

    test("External (gesture / CLI) sessions") {
        var m = machine()
        let session = m.startExternal()
        check(m.isActive && m.isPinned)
        check(m.handle(flags([])).intents.isEmpty)
        check(m.handle(down(KeyCode.tab)).intents == [.move(1)])
        check(m.handle(down(KeyCode.escape)).intents == [.cancel(session: session)])
        check(!m.isActive)
    }

    test("Several shortcuts, ⌘ shortcuts and shortcuts containing ⇧") {
        let shortcuts = [
            ShortcutConfig(keyCode: KeyCode.tab, modifiers: command.rawValue),
            ShortcutConfig(keyCode: KeyCode.grave, modifiers: command.rawValue, apps: .active),
            ShortcutConfig(keyCode: 1, modifiers: option.union(shift).rawValue),
        ]
        var m = machine(shortcuts)
        check(m.handle(down(KeyCode.grave, command)).intents == [.begin(session: 1, shortcut: 1, reverse: false)])
        check(m.handle(down(KeyCode.grave, command)).intents == [.move(1)], "the shortcut's own key cycles")
        check(m.handle(flags(option)).intents == [.commit(session: 1)], "releasing ⌘ switches")
        check(!m.handle(down(1, option)).swallow, "⌥S doesn't match ⌥⇧S")
        check(m.handle(down(1, option.union(shift))).intents == [.begin(session: 2, shortcut: 2, reverse: false)], "⇧ is part of it, not reverse")
        check(m.handle(down(1, option.union(shift))).intents == [.move(1)])
    }

    test("Invalid shortcuts never trigger") {
        var m = machine([ShortcutConfig(keyCode: KeyCode.tab, modifiers: shift.rawValue)])
        check(!m.handle(down(KeyCode.tab, shift)).swallow)
        check(!m.isActive)
    }

    test("Stale swallowed key-ups are forgotten") {
        var m = machine()
        _ = m.handle(down(KeyCode.tab, option))
        _ = m.handle(flags([]))
        // The Tab key-up got lost somewhere. The next plain Tab press must work normally.
        check(!m.handle(down(KeyCode.tab)).swallow)
        check(!m.handle(up(KeyCode.tab)).swallow, "its key-up isn't eaten")
    }

    test("Fuzz: 300k random events keep the machine consistent") {
        var rng = SeededGenerator(seed: 42)
        let shortcuts = ShortcutConfig.defaults + [ShortcutConfig(keyCode: KeyCode.tab, modifiers: command.rawValue)]
        var m = machine(shortcuts)
        var open: Set<Int> = []
        var closed: Set<Int> = []
        var downKeys: Set<Int64> = []
        let keyPool: [Int64] = [KeyCode.tab, KeyCode.grave, KeyCode.escape, KeyCode.returnKey, KeyCode.left, KeyCode.up,
                                KeyCode.delete, 0, 1, 12, 49]
        let flagPool: [CGEventFlags] = [[], option, command, shift, option.union(shift), command.union(shift), option.union(command), .maskControl]
        for i in 0..<300_000 {
            if i % 5000 == 0 { m.keepOpen = Bool.random(using: &rng) }
            let f = flagPool.randomElement(using: &rng)!
            let key = keyPool.randomElement(using: &rng)!
            let input: KeyInput
            switch Int.random(in: 0..<10, using: &rng) {
            case 0...3: input = down(key, f, key == 0 ? "a" : key == 49 ? " " : nil)
            case 4...6: input = up(key, f)
            case 7: input = flags(f)
            case 8:
                if m.isActive { m.end(session: m.session) }
                continue
            default:
                if !m.isActive { _ = m.startExternal(); open.insert(m.session) }
                continue
            }
            let wasActive = m.isActive
            let (swallow, intents) = m.handle(input)
            if input.kind == .keyDown { if swallow { downKeys.insert(key) } }
            if input.kind == .keyUp && swallow {
                check(downKeys.remove(key) != nil, "swallowed a key-up we never swallowed the key-down of")
            }
            if input.kind == .keyDown && wasActive { check(swallow, "every key is swallowed while switching") }
            if input.kind == .flagsChanged { check(!swallow, "modifier changes are never swallowed") }
            for intent in intents {
                switch intent {
                case let .begin(session, _, _):
                    check(!open.contains(session) && !closed.contains(session), "session ids are unique")
                    open.insert(session)
                case let .commit(session), let .cancel(session):
                    check(open.contains(session) && !closed.contains(session), "end of a session that isn't open")
                    closed.insert(session)
                default:
                    check(wasActive, "moves only while active")
                }
            }
            if m.isActive && !m.isPinned, let index = m.activeShortcut, input.kind == .flagsChanged {
                check(f.contains(shortcuts[index].holdFlags), "active while the shortcut's modifiers aren't held")
            }
        }
    }
}

/// Deterministic random numbers so failures reproduce.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
