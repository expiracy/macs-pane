import Foundation

/// Keys setup offers for a box of a built-in layout, off until you switch them on.
public struct ShortcutSuggestion: Equatable, Identifiable, Sendable {
    public let name: String
    public let action: ShortcutAction
    public let shortcut: KeyShortcut

    public var id: String { name }

    /// ⌃⌥ with an arrow, Return or C, as window managers on the Mac tend to use them.
    static let all: [ShortcutSuggestion] = {
        let ctrlOpt: KeyShortcut.Modifiers = [.control, .option]
        return [
            ShortcutSuggestion(name: "Left half", action: .layoutBox(layoutID: "halves", box: 0),
                               shortcut: KeyShortcut(keyCode: 123, modifiers: ctrlOpt)),
            ShortcutSuggestion(name: "Right half", action: .layoutBox(layoutID: "halves", box: 1),
                               shortcut: KeyShortcut(keyCode: 124, modifiers: ctrlOpt)),
            ShortcutSuggestion(name: "Fill", action: .layoutBox(layoutID: "fill", box: 0),
                               shortcut: KeyShortcut(keyCode: 36, modifiers: ctrlOpt)),
            ShortcutSuggestion(name: "Centre", action: .layoutBox(layoutID: "centre", box: 0),
                               shortcut: KeyShortcut(keyCode: 8, modifiers: ctrlOpt, character: "c")),
        ]
    }()
}

extension MacsPaneConfig {
    /// The suggestions whose box is still there: a deleted layout's are left out.
    public var shortcutSuggestions: [ShortcutSuggestion] {
        let catalog = windows.layoutCatalog
        return ShortcutSuggestion.all.filter { suggestion in
            guard case let .layoutBox(layoutID, box) = suggestion.action else { return false }
            return catalog.first { $0.id == layoutID }.map { $0.boxes.indices.contains(box) } ?? false
        }
    }

    /// The keys the box has, or the suggested ones while it has none.
    public func keys(for suggestion: ShortcutSuggestion) -> KeyShortcut {
        shortcut(for: suggestion.action) ?? suggestion.shortcut
    }

    public func isOn(_ suggestion: ShortcutSuggestion) -> Bool {
        shortcuts.first { $0.action == suggestion.action }?.isEnabled ?? false
    }

    /// On gives the box the suggested keys, or switches on the keys it already has; off keeps the keys,
    /// switched off, as the menu's switch does.
    public mutating func setSuggestion(_ suggestion: ShortcutSuggestion, on: Bool) {
        if shortcut(for: suggestion.action) == nil {
            guard on else { return }
            setShortcut(suggestion.shortcut, for: suggestion.action)
        }
        setShortcutEnabled(on, for: suggestion.action)
    }
}
