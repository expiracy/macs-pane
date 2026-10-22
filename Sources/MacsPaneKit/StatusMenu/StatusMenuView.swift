#if canImport(AppKit)
import SwiftUI

/// What the menu-bar dropdown shows and does. Rebuilt from the registry on open, after every click
/// that leaves it open, and once a second while it is open (the timer counts down in front of you).
final class StatusMenuModel: ObservableObject {
    @Published private(set) var content = StatusMenuContent()
    /// The name over the dropdown and its section titles.
    let brand: StatusMenuBrand
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}
    /// Set by the panel's owner; commands and grants close the dropdown before they act.
    var onClose: () -> Void = {}
    private let assemble: () -> StatusMenuContent

    init(brand: StatusMenuBrand, assemble: @escaping () -> StatusMenuContent) {
        self.brand = brand
        self.assemble = assemble
        refresh()
    }

    func refresh() {
        content = assemble()
    }

    func pick(_ entry: StatusMenuEntry, index: Int) {
        entry.select?(index)
        refresh()
    }

    /// A live line clicked off its button: close, then show its page in the notch.
    func open(_ entry: StatusMenuEntry) {
        guard let open = entry.open else { return }
        onClose()
        open()
    }

    func run(_ entry: StatusMenuEntry) {
        guard let action = entry.action else { return }
        switch entry.kind {
        case .toggle, .live, .choice:
            action()
            refresh()
            // An owner that settles a beat later (the quiet bell) is read again once it has.
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        case .command, .warning, .section:
            onClose()
            action()
        }
    }
}

/// The dropdown's name and section titles.
struct StatusMenuBrand {
    var name: String
    /// The title over the box of what is live.
    var liveTitle = "Now"
    /// The box's line when nothing is live; nil leaves the box out until something is.
    var emptyLive: String? = "Nothing running"
    /// The title over the switches.
    var togglesTitle = "Notch"
}

/// The menu-bar icon's dropdown: a native panel hanging under the icon in place of
/// a system menu. Top to bottom — the mark, the name and the app's main switch; a box of what is
/// running now, one button per line; warnings; the remaining switches; the titled command sections;
/// Settings and Quit. It is an ordinary macOS surface (only the notch is dark):
/// system type, switches, buttons and colours on the menu material its panel supplies, following
/// the system's light or dark appearance. No notch tokens or palette in this file.
struct StatusMenuView: View {
    @ObservedObject var model: StatusMenuModel
    @State private var hoveredCommand: String?

    /// The panel's own measures; a system menu's proportions, a little roomier at the edges.
    private enum Metric {
        static let width: CGFloat = 300
        static let edge: CGFloat = 10
        static let row: CGFloat = 30
        static let inset: CGFloat = 8
        static let icon: CGFloat = 18
        static let corner: CGFloat = 6
        /// Fits the longest verb ("Resume"), so every live button is one width.
        static let verb: CGFloat = 58
    }

    var body: some View {
        let content = model.content
        VStack(spacing: 0) {
            header(content)
            if !content.live.isEmpty || model.brand.emptyLive != nil { runningNow(content.live) }
            ForEach(content.warnings) { row($0) }
            if !content.toggles.isEmpty { sectionTitle(model.brand.togglesTitle) }
            ForEach(content.toggles + content.commands) { entry in
                row(entry)
            }
            footer
        }
        .padding(Metric.edge)
        .frame(width: Metric.width)
    }

    private func header(_ content: StatusMenuContent) -> some View {
        HStack(spacing: 8) {
            mark
            VStack(alignment: .leading, spacing: 1) {
                Text(model.brand.name).font(.headline)
                if let fact = content.liveFact {
                    Text(fact).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let primary = content.primary, case let .toggle(isOn, _, _) = primary.kind {
                switchControl(primary, isOn: isOn)
            }
        }
        .padding(.horizontal, Metric.inset)
        .frame(height: 36)
        .padding(.bottom, 2)
    }

    private var mark: some View { MacsPaneLogo(size: 22) }

    /// With an `emptyLive` line the box is always there, holding that line when nothing is live; without
    /// one the box shows only while it has something in it.
    private func runningNow(_ live: [StatusMenuEntry]) -> some View {
        VStack(spacing: 0) {
            sectionTitle(model.brand.liveTitle)
            VStack(spacing: 0) {
                if live.isEmpty, let empty = model.brand.emptyLive {
                    Text(empty).font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, Metric.inset)
                        .frame(maxWidth: .infinity, minHeight: Metric.row, alignment: .leading)
                }
                ForEach(live) { entry in
                    liveRow(entry)
                }
            }
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: Metric.corner + 2, style: .continuous).fill(.primary.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metric.corner + 2, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
            .padding(.bottom, 6)
        }
    }

    /// Icon · what it is · its live fact · the one thing to do to it. Every button takes the width
    /// of the longest verb, so the facts line up and Pause turning into Resume moves nothing. The
    /// line itself is a second, larger target: it highlights like a menu row and opens the notch on
    /// the page with the detail.
    @ViewBuilder private func liveRow(_ entry: StatusMenuEntry) -> some View {
        if case let .live(fact, actionTitle, accent) = entry.kind {
            HStack(spacing: 6) {
                glyph(entry)
                Text(entry.title).lineLimit(1).truncationMode(.tail)
                    .help(entry.open == nil ? entry.title : "\(entry.title) · click to open it in the notch")
                Spacer(minLength: 4)
                Text(fact).font(.callout).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
                if let actionTitle {
                    liveButton(entry, title: actionTitle, accent: accent)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, actionTitle == nil ? Metric.inset : 0)
            .frame(height: Metric.row)
            .background {
                RoundedRectangle(cornerRadius: Metric.corner, style: .continuous)
                    .fill(.primary.opacity(entry.open != nil && hoveredCommand == entry.id ? 0.08 : 0))
            }
            .contentShape(Rectangle())
            .onHover { hoveredCommand = $0 ? entry.id : (hoveredCommand == entry.id ? nil : hoveredCommand) }
            .onTapGesture { model.open(entry) }
            .accessibilityAction(named: "Open in the notch") { model.open(entry) }
        }
    }

    @ViewBuilder private func liveButton(_ entry: StatusMenuEntry, title: String, accent: Bool) -> some View {
        let button = Button { model.run(entry) } label: {
            Text(title).frame(width: Metric.verb - 16)
        }
        .controlSize(.small)
        if accent { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Metric.inset)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .bottomLeading)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func row(_ entry: StatusMenuEntry) -> some View {
        switch entry.kind {
        case .section:
            sectionTitle(entry.title)
        case .live:
            liveRow(entry)
        case let .toggle(isOn, disabled, _):
            HStack(spacing: 6) {
                glyph(entry)
                Text(entry.title).lineLimit(1)
                Spacer(minLength: 4)
                switchControl(entry, isOn: isOn)
            }
            .padding(.horizontal, Metric.inset)
            .frame(height: Metric.row)
            .disabled(disabled)
        case let .choice(options, selected):
            choiceRow(entry, options: options, selected: selected)
        case let .command(danger):
            commandRow(entry, danger: danger)
        case let .warning(actionTitle):
            warning(entry, actionTitle: actionTitle)
        }
    }

    private func choiceRow(_ entry: StatusMenuEntry, options: [String], selected: Int) -> some View {
        HStack(spacing: 6) {
            glyph(entry)
            Text(entry.title).lineLimit(1)
            Spacer(minLength: 4)
            Picker(entry.title, selection: Binding(get: { selected }, set: { model.pick(entry, index: $0) })) {
                ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, Metric.inset)
        .frame(height: Metric.row)
    }

    /// A menu-style row: the whole line is the target and highlights under the pointer.
    private func commandRow(_ entry: StatusMenuEntry, danger: Bool) -> some View {
        Button { model.run(entry) } label: {
            HStack(spacing: 6) {
                glyph(entry)
                Text(entry.title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(danger ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            .padding(.horizontal, Metric.inset)
            .frame(height: Metric.row - 4)
            .background {
                RoundedRectangle(cornerRadius: Metric.corner, style: .continuous)
                    .fill(.primary.opacity(hoveredCommand == entry.id ? 0.1 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredCommand = $0 ? entry.id : (hoveredCommand == entry.id ? nil : hoveredCommand) }
    }

    /// The system switch, wired to the entry's own action so the registry stays the one source of state.
    private func switchControl(_ entry: StatusMenuEntry, isOn: Bool) -> some View {
        Toggle(entry.title, isOn: Binding(get: { isOn }, set: { _ in model.run(entry) }))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }

    private func glyph(_ entry: StatusMenuEntry) -> some View {
        Image(systemName: entry.symbol ?? "circle")
            .foregroundStyle(.secondary)
            .frame(width: Metric.icon)
            .accessibilityHidden(true)
    }

    /// The orange line carries the reason; its button is the one click that fixes it.
    private func warning(_ entry: StatusMenuEntry, actionTitle: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: Metric.icon)
                .accessibilityHidden(true)
            Text(entry.title).font(.callout).lineLimit(1)
                .help(entry.title)
            Spacer(minLength: 4)
            if let actionTitle {
                Button(actionTitle) { model.run(entry) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, Metric.inset)
        .frame(height: Metric.row)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                footerButton("Settings", symbol: "gearshape", key: "⌘,", action: model.onSettings)
                footerButton("Quit", symbol: "power", key: "⌘Q", action: model.onQuit)
            }
        }
        .padding(.top, 8)
    }

    private func footerButton(_ title: String, symbol: String, key: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).accessibilityHidden(true)
                Text(title)
                Text(key).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(title)
    }
}
#endif
