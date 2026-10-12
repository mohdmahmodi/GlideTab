import AppKit
import Carbon.HIToolbox

enum KeyCode {
    static let tab: Int64 = 48, grave: Int64 = 50, escape: Int64 = 53, returnKey: Int64 = 36, enter: Int64 = 76
    static let delete: Int64 = 51, forwardDelete: Int64 = 117, space: Int64 = 49
    static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
}

/// One user-defined switcher shortcut: the keys, plus which windows it shows.
struct ShortcutConfig: Codable, Equatable, Identifiable {
    enum AppFilter: String, Codable, CaseIterable, Identifiable {
        case all, active
        var id: Self { self }
        var title: String { self == .all ? String(localized: "All Apps") : String(localized: "Active App") }
    }

    enum SpaceFilter: String, Codable, CaseIterable, Identifiable {
        case all, current
        var id: Self { self }
        var title: String { self == .all ? String(localized: "All Spaces") : String(localized: "Current Space") }
    }

    enum ScreenFilter: String, Codable, CaseIterable, Identifiable {
        case all, current
        var id: Self { self }
        var title: String { self == .all ? String(localized: "All Screens") : String(localized: "Current Screen") }
    }

    enum Visibility: String, Codable, CaseIterable, Identifiable {
        case show, hide, atEnd
        var id: Self { self }
        var title: String {
            switch self {
            case .show: String(localized: "Show")
            case .hide: String(localized: "Hide")
            case .atEnd: String(localized: "Show at the end")
            }
        }
    }

    var id = UUID()
    var keyCode: Int64
    /// CGEventFlags raw value, limited to ⌘ ⌥ ⌃ ⇧.
    var modifiers: UInt64
    var apps = AppFilter.all
    var spaces = SpaceFilter.all
    var screens = ScreenFilter.all
    var minimized = Visibility.show
    var hidden = Visibility.show

    init(keyCode: Int64, modifiers: UInt64, apps: AppFilter = .all, spaces: SpaceFilter = .all, screens: ScreenFilter = .all) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.apps = apps
        self.spaces = spaces
        self.screens = screens
    }

    /// Missing fields fall back to their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        keyCode = try c.decode(Int64.self, forKey: .keyCode)
        modifiers = try c.decode(UInt64.self, forKey: .modifiers)
        apps = try c.decodeIfPresent(AppFilter.self, forKey: .apps) ?? .all
        spaces = try c.decodeIfPresent(SpaceFilter.self, forKey: .spaces) ?? .all
        screens = try c.decodeIfPresent(ScreenFilter.self, forKey: .screens) ?? .all
        minimized = try c.decodeIfPresent(Visibility.self, forKey: .minimized) ?? .show
        hidden = try c.decodeIfPresent(Visibility.self, forKey: .hidden) ?? .show
    }

    private static let holdable: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
    static let recordable: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    static let maxCount = 9

    static let defaults = [
        ShortcutConfig(keyCode: KeyCode.tab, modifiers: CGEventFlags.maskAlternate.rawValue),
        ShortcutConfig(keyCode: KeyCode.grave, modifiers: CGEventFlags.maskAlternate.rawValue, apps: .active),
    ]

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers).intersection(Self.recordable) }
    /// Modifiers that keep the switcher open while held. ⇧ isn't one: it reverses direction.
    var holdFlags: CGEventFlags { flags.intersection(Self.holdable) }
    /// A shortcut needs at least one of ⌘ ⌥ ⌃, so there's something to release.
    var isValid: Bool { !holdFlags.isEmpty }
    var isCommandTab: Bool { keyCode == KeyCode.tab && holdFlags == .maskCommand }
    var displayString: String { KeyNames.symbols(for: flags) + KeyNames.name(for: keyCode) }

    /// Applies this shortcut's minimized / hidden rules to an ordered list.
    func arrange(_ windows: [WindowInfo]) -> [WindowInfo] {
        func rank(_ w: WindowInfo) -> Visibility {
            if w.isMinimized && minimized != .show { return minimized }
            if w.app.isHidden && hidden != .show { return hidden }
            return .show
        }
        let visible = windows.filter { rank($0) != .hide }
        return visible.filter { rank($0) == .show } + visible.filter { rank($0) == .atEnd }
    }

    func matches(keyCode: Int64, flags eventFlags: CGEventFlags) -> Bool {
        keyCode == self.keyCode
            && eventFlags.intersection(Self.holdable) == holdFlags
            && (!flags.contains(.maskShift) || eventFlags.contains(.maskShift))
    }

    func sameKeys(as other: ShortcutConfig) -> Bool {
        keyCode == other.keyCode && flags == other.flags
    }
}

enum KeyNames {
    private static let special: [Int64: String] = [
        KeyCode.tab: "⇥", KeyCode.space: String(localized: "Space"), KeyCode.returnKey: "↩", KeyCode.enter: "⌤", KeyCode.escape: "⎋",
        KeyCode.delete: "⌫", KeyCode.forwardDelete: "⌦", KeyCode.left: "←", KeyCode.right: "→", KeyCode.up: "↑",
        KeyCode.down: "↓", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 122: "F1", 120: "F2", 99: "F3", 118: "F4",
        96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// In Apple's standard order: ⌃ ⌥ ⇧ ⌘
    static func symbols(for flags: CGEventFlags) -> String {
        var result = ""
        if flags.contains(.maskControl) { result += "⌃" }
        if flags.contains(.maskAlternate) { result += "⌥" }
        if flags.contains(.maskShift) { result += "⇧" }
        if flags.contains(.maskCommand) { result += "⌘" }
        return result
    }

    /// The key's label on the current keyboard layout (so ` shows as ` on US, < on some European layouts).
    static func name(for keyCode: Int64) -> String {
        if let name = special[keyCode] { return name }
        return translate(keyCode, shifted: false)?.uppercased() ?? "#\(keyCode)"
    }

    /// What the key types on its own and with ⇧, for drawing a real key cap (e.g. "`" and "~").
    static func characters(for keyCode: Int64) -> (normal: String, shifted: String)? {
        guard special[keyCode] == nil, let normal = translate(keyCode, shifted: false) else { return nil }
        return (normal, translate(keyCode, shifted: true) ?? normal)
    }

    private static func translate(_ keyCode: Int64, shifted: Bool) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let modifiers: UInt32 = shifted ? UInt32(shiftKey >> 8) & 0xFF : 0
        let status = layout.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(base, UInt16(keyCode), UInt16(kUCKeyActionDisplay), modifiers, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
