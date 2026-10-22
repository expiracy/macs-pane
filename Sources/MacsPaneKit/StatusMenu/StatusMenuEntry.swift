#if canImport(AppKit)
import Foundation

/// The menu-bar dropdown's content, sorted into the bands `StatusMenuView` draws top to bottom.
struct StatusMenuContent {
    /// The app's main switch, beside the name.
    var primary: StatusMenuEntry?
    /// What is running right now; empty draws one quiet line.
    var live: [StatusMenuEntry] = []
    var warnings: [StatusMenuEntry] = []
    /// The notch's global settings: switches and choices.
    var toggles: [StatusMenuEntry] = []
    /// Titled sections and their commands, in the order contributed.
    var commands: [StatusMenuEntry] = []
    /// A line under the name; nil for none.
    var liveFact: String?
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
                       action: @escaping () -> Void) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: symbol,
                        kind: .toggle(isOn: isOn, disabled: disabled, primary: primary), action: action)
    }

    static func command(_ title: String, symbol: String, danger: Bool = false,
                        action: @escaping () -> Void) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: symbol, kind: .command(danger: danger), action: action)
    }

    static func warning(_ title: String, actionTitle: String? = nil,
                        action: (() -> Void)? = nil) -> StatusMenuEntry {
        StatusMenuEntry(title: title, symbol: "exclamationmark.triangle",
                        kind: .warning(actionTitle: actionTitle), action: action)
    }
}
#endif
