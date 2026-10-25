import Foundation

/// What a shortcut does: send the window you are in to one box of a layout, or apply a preset.
/// A box is named by its place in the layout's boxes, so the built-in layouts, which are never
/// saved, can have shortcuts too.
public enum ShortcutAction: Hashable, Sendable {
    case layoutBox(layoutID: String, box: Int)
    case preset(id: String)
}

extension ShortcutAction: Codable {
    private enum CodingKeys: String, CodingKey { case kind, layoutID, box, id }
    private enum Kind: String, Codable { case layoutBox, preset }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .layoutBox:
            self = .layoutBox(layoutID: try c.decode(String.self, forKey: .layoutID),
                              box: try c.decode(Int.self, forKey: .box))
        case .preset:
            self = .preset(id: try c.decode(String.self, forKey: .id))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .layoutBox(let layoutID, let box):
            try c.encode(Kind.layoutBox, forKey: .kind)
            try c.encode(layoutID, forKey: .layoutID)
            try c.encode(box, forKey: .box)
        case .preset(let id):
            try c.encode(Kind.preset, forKey: .kind)
            try c.encode(id, forKey: .id)
        }
    }
}

/// One shortcut and what it does, and whether it is switched on. Saved in `MacsPaneConfig.shortcuts`;
/// an entry that will not decode (no key, an action from a newer build) is dropped alone.
public struct AssignedShortcut: Codable, Equatable, Sendable {
    public var shortcut: KeyShortcut
    public var action: ShortcutAction
    /// Off keeps the keys for later but lets them through to the app you're in. Absent in files from
    /// before the switch, which are on.
    public var isEnabled: Bool

    public init(shortcut: KeyShortcut, action: ShortcutAction, isEnabled: Bool = true) {
        self.shortcut = shortcut
        self.action = action
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey { case shortcut, action, isEnabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.shortcut = try c.decode(KeyShortcut.self, forKey: .shortcut)
        self.action = try c.decode(ShortcutAction.self, forKey: .action)
        self.isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
    }
}

extension MacsPaneConfig {
    public func shortcut(for action: ShortcutAction) -> KeyShortcut? {
        shortcuts.first { $0.action == action }?.shortcut
    }

    /// Give `action` a shortcut, or take its shortcut away (nil). A combo does one thing: whatever
    /// had it before loses it. The same keys saved again stay switched as they were; new keys are on.
    public mutating func setShortcut(_ shortcut: KeyShortcut?, for action: ShortcutAction) {
        let wasOff = shortcuts.contains { $0.action == action && $0.shortcut == shortcut && !$0.isEnabled }
        shortcuts.removeAll { $0.action == action || $0.shortcut == shortcut }
        if let shortcut { shortcuts.append(AssignedShortcut(shortcut: shortcut, action: action, isEnabled: !wasOff)) }
    }

    /// Switch an action's shortcut on or off, keeping its keys.
    public mutating func setShortcutEnabled(_ enabled: Bool, for action: ShortcutAction) {
        guard let index = shortcuts.firstIndex(where: { $0.action == action }) else { return }
        shortcuts[index].isEnabled = enabled
    }

    /// A layout's box shortcuts, by box index.
    public func boxShortcuts(ofLayout id: String) -> [Int: KeyShortcut] {
        var byBox: [Int: KeyShortcut] = [:]
        for case let (shortcut, .layoutBox(layoutID, box)) in shortcuts.map({ ($0.shortcut, $0.action) })
            where layoutID == id {
            byBox[box] = shortcut
        }
        return byBox
    }

    /// Replace every box shortcut of a layout, as its editor saves them. A box saved with the keys it
    /// had stays switched as it was.
    public mutating func setBoxShortcuts(_ byBox: [Int: KeyShortcut], ofLayout id: String) {
        let off = shortcuts.filter { !$0.isEnabled }
        shortcuts.removeAll {
            if case .layoutBox(id, _) = $0.action { return true }
            return false
        }
        for (box, shortcut) in byBox.sorted(by: { $0.key < $1.key }) {
            let action = ShortcutAction.layoutBox(layoutID: id, box: box)
            setShortcut(shortcut, for: action)
            if off.contains(where: { $0.action == action && $0.shortcut == shortcut }) {
                setShortcutEnabled(false, for: action)
            }
        }
    }

    /// The shortcuts that answer a key now: the listed ones that are switched on.
    public var activeShortcuts: [AssignedShortcut] { shortcutList.filter(\.isEnabled) }

    /// The shortcuts with something to run, on or off: usable ones whose preset, layout and box exist.
    /// A deleted built-in keeps its shortcuts, unlisted, for when it is restored.
    private var runnableShortcuts: [AssignedShortcut] {
        let presetIDs = Set(presets.map(\.id))
        let boxCounts = Dictionary(windows.layoutCatalog.map { ($0.id, $0.boxes.count) },
                                   uniquingKeysWith: { first, _ in first })
        return shortcuts.filter { assigned in
            guard assigned.shortcut.isUsable else { return false }
            switch assigned.action {
            case .preset(let id): return presetIDs.contains(id)
            case .layoutBox(let layoutID, let box): return (0..<(boxCounts[layoutID] ?? 0)).contains(box)
            }
        }
    }

    /// Every shortcut with something to run, on or off, as the menu lists them: presets in their
    /// order, then layout boxes, by layout in the menu's order and then by box.
    public var shortcutList: [AssignedShortcut] {
        let presetOrder = Dictionary(presets.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let layoutOrder = Dictionary(windows.layoutCatalog.enumerated().map { ($1.id, $0) },
                                     uniquingKeysWith: { first, _ in first })
        func place(_ action: ShortcutAction) -> (Int, Int, Int) {
            switch action {
            case .preset(let id): return (0, presetOrder[id] ?? .max, 0)
            case let .layoutBox(layoutID, box): return (1, layoutOrder[layoutID] ?? .max, box)
            }
        }
        return runnableShortcuts.sorted { place($0.action) < place($1.action) }
    }

    /// Delete a layout, as `WindowsConfig.removeLayout` does; one of yours takes its shortcuts with it.
    public mutating func removeLayout(_ id: String) -> WindowsConfig.RemovedLayout? {
        let removed = windows.removeLayout(id)
        if removed != nil, !WindowLayout.builtIns.contains(where: { $0.id == id }) {
            setBoxShortcuts([:], ofLayout: id)
        }
        return removed
    }
}
