#if canImport(AppKit)
import Foundation
import MacsPaneCore

/// The menu-bar dropdown's content, sorted into the bands `StatusMenuView` draws top to bottom.
struct StatusMenuContent {
    /// The app's main switch, beside the name.
    var primary: StatusMenuEntry?
    /// What is running right now; empty draws one quiet line.
    var live: [StatusMenuEntry] = []
    var warnings: [StatusMenuEntry] = []
    /// The notch's global settings: switches and choices.
    var toggles: [StatusMenuEntry] = []
    /// Titled lists (presets, layouts), in the order contributed. A long list scrolls in place.
    var groups: [StatusMenuGroup] = []
    /// A line under the name; nil for none.
    var liveFact: String?
}

/// A titled list in the dropdown: its rows, which scroll once there are more than fit, then the
/// commands that always show under them ("New preset…").
struct StatusMenuGroup: Identifiable {
    let title: String
    var rows: [StatusMenuEntry]
    var actions: [StatusMenuEntry] = []
    /// The line shown in place of rows when there are none.
    var empty: String?
    /// Set when the rows can be dragged into another order: moves the row at the first index so it
    /// ends up at the second.
    var move: ((Int, Int) -> Void)?
    var id: String { title }
}

/// One line of the menu-bar dropdown (`StatusMenuView` draws them).
struct StatusMenuEntry: Identifiable {
    enum Kind {
        /// A text-only title over the rows beneath it.
        case section
        /// One of the notch's live activities, for the "Running now" box: what it is, one live fact,
        /// and the one thing you would do to it from here (`accent` for the action that is the point
        /// of the line, such as Join; nil when there is nothing to do but know). The dropdown stays
        /// open and re-reads state after the click.
        case live(fact: String, actionTitle: String?, accent: Bool)
        /// A setting with a few named values, shown side by side; `selected` indexes `options`.
        case choice(options: [String], selected: Int)
        /// A setting that stays put: the row's switch is its one target and the dropdown stays open.
        /// A switch that cannot act now is `disabled` and keeps its row, so nothing below it moves.
        /// `primary` is the app's main switch, which sits in the name band instead of the rows.
        case toggle(isOn: Bool, disabled: Bool, primary: Bool)
        /// Something done once; the dropdown closes. `danger` is a last-resort command.
        case command(danger: Bool)
        /// A feature that is on but cannot run, with the one click that fixes it (nil = nothing to click).
        case warning(actionTitle: String?)
    }

    let title: String
    var symbol: String?
    let kind: Kind
    var action: (() -> Void)?
    /// A live line's click anywhere but its button: open the notch page that holds its detail. The
    /// dropdown closes first.
    var open: (() -> Void)?
    /// A choice's pick, by index into its options.
    var select: ((Int) -> Void)?
    /// A command's second button, at the row's end (Edit beside a preset you apply by clicking the row).
    /// The dropdown closes first.
    var secondary: (symbol: String, help: String, action: () -> Void)?
    /// A row's trash button, beside its second button: deletes the item straight away (the Last change
    /// box offers it back). The dropdown stays open.
    var trash: (help: String, action: () -> Void)?
    /// A layout's or preset's boxes, drawn as a small screen in place of the symbol.
    var boxes: [SnapRegion]?
    /// Identity when titles can repeat (two meetings with one name); nil uses the title.
    var key: String?

    var id: String { key ?? title }

    static func section(_ title: String) -> StatusMenuEntry {
        StatusMenuEntry(title: title, kind: .section)
    }

    static func live(_ title: String, symbol: String, fact: String, actionTitle: String? = nil,
                     accent: Bool = false, key: String? = nil, action: (() -> Void)? = nil) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: symbol,
                        kind: .live(fact: fact, actionTitle: actionTitle, accent: accent), action: action, key: key)
    }

    static func choice(_ title: String, symbol: String, options: [String], selected: Int,
                       select: @escaping (Int) -> Void) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: symbol, kind: .choice(options: options, selected: selected),
                        select: select)
    }

    static func toggle(_ title: String, symbol: String, isOn: Bool, disabled: Bool = false, primary: Bool = false,
                       key: String? = nil, boxes: [SnapRegion]? = nil,
                       secondary: (symbol: String, help: String, action: () -> Void)? = nil,
                       trash: (help: String, action: () -> Void)? = nil,
                       action: @escaping () -> Void) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: symbol,
                        kind: .toggle(isOn: isOn, disabled: disabled, primary: primary), action: action,
                        secondary: secondary, trash: trash, boxes: boxes, key: key)
    }

    static func command(_ title: String, symbol: String, danger: Bool = false, key: String? = nil,
                        boxes: [SnapRegion]? = nil,
                        secondary: (symbol: String, help: String, action: () -> Void)? = nil,
                        trash: (help: String, action: () -> Void)? = nil,
                        action: @escaping () -> Void) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: symbol, kind: .command(danger: danger), action: action,
                        secondary: secondary, trash: trash, boxes: boxes, key: key)
    }

    static func warning(_ title: String, actionTitle: String? = nil,
                        action: (() -> Void)? = nil) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: "exclamationmark.triangle",
                        kind: .warning(actionTitle: actionTitle), action: action)
    }
}
#endif
