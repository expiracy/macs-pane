import Foundation

/// A key combination pressed anywhere to run a MacsPane action: a key, by its hardware key code, and
/// the modifiers held with it. `character` is what the key typed when it was recorded, on the
/// keyboard layout of the day, kept only to write the shortcut out ("⌃⌥1").
public struct KeyShortcut: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers
    public var character: String?

    public init(keyCode: UInt16, modifiers: Modifiers, character: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.character = character
    }

    /// Whether it can be taken from every app: it needs ⌘, ⌃ or ⌥, or a function key, so it never
    /// eats what you type.
    public var isUsable: Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option]) || Self.functionKeys.contains(keyCode)
    }

    /// The shortcut as macOS menus write it: ⌃⌥⇧⌘, then the key.
    public var displayName: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyName
    }

    /// The key alone: its symbol or name for keys that type nothing, else what it typed.
    public var keyName: String {
        if let name = Self.specialKeyNames[keyCode] { return name }
        if let character, !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return character.uppercased()
        }
        return "Key \(keyCode)"
    }

    /// Keys that type nothing visible, by key code (the US-layout hardware codes macOS uses on
    /// every layout).
    static let specialKeyNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static let functionKeys = Set(specialKeyNames.filter { $0.value.hasPrefix("F") }.keys)
}

extension KeyShortcut: Codable {
    private enum CodingKeys: String, CodingKey { case keyCode, modifiers, character }

    /// A shortcut with no key code means nothing and throws, so the list holding it drops it alone.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        self.modifiers = (try? c.decodeIfPresent(Modifiers.self, forKey: .modifiers)) ?? []
        self.character = try? c.decodeIfPresent(String.self, forKey: .character)
    }
}
