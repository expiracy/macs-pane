#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// What the menu-bar dropdown shows and does. Rebuilt from the registry on open, after every click
/// that leaves it open, and once a second while it is open (the timer counts down in front of you).
final class StatusMenuModel: ObservableObject {
    @Published private(set) var content = StatusMenuContent()
    /// The name over the dropdown and its section titles.
    let brand: StatusMenuBrand
    /// Opens the first-time setup again (the footer's Setup button).
    var onSetup: () -> Void = {}
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

    /// A command row's second button.
    func runSecondary(_ entry: StatusMenuEntry) {
        guard let secondary = entry.secondary else { return }
        onClose()
        secondary.action()
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

/// The menu-bar icon's dropdown, in the same style as the rest of MacsPane (setup, the editor, the
/// prompts): a solid panel; the mark, the name and the main switch; then rounded cards, each under a
/// small title: the last change with its Undo, any warning with its fix, the general switches, and
/// the titled lists (presets, layouts). Rows lead with a tinted icon tile, or a layout's own shape.
/// A long list scrolls inside its card. Setup and Quit sit at the foot.
struct StatusMenuView: View {
    @ObservedObject var model: StatusMenuModel
    @State private var hoveredRow: String?

    private enum Metric {
        static let width: CGFloat = 320
        static let edge: CGFloat = 12
        static let row: CGFloat = 38
        static let corner: CGFloat = 12
        static let tile: CGFloat = 24
        /// A list taller than this many rows scrolls; the half row peeking out says there is more.
        static let visibleRows: CGFloat = 5.5
    }

    var body: some View {
        let content = model.content
        VStack(alignment: .leading, spacing: 14) {
            header(content)
            if !content.live.isEmpty || model.brand.emptyLive != nil { liveCard(content.live) }
            ForEach(content.warnings) { warningCard($0) }
            if !content.toggles.isEmpty {
                card(model.brand.togglesTitle) { rows(content.toggles) }
            }
            ForEach(content.groups) { groupCard($0) }
            footer
        }
        .padding(Metric.edge)
        .frame(width: Metric.width)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Bands

    private func header(_ content: StatusMenuContent) -> some View {
        HStack(spacing: 10) {
            MacsPaneLogo(size: 32)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.brand.name).font(.system(size: 15, weight: .semibold))
                if let line = content.liveFact ?? content.primary?.title {
                    Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let primary = content.primary, case let .toggle(isOn, _, _) = primary.kind {
                switchControl(primary, isOn: isOn)
            }
        }
        .padding(.horizontal, 4)
    }

    /// The last change, laid out as the on-screen Undo prompt is: its icon, what happened, the one button.
    private func liveCard(_ live: [StatusMenuEntry]) -> some View {
        card(model.brand.liveTitle) {
            if live.isEmpty, let empty = model.brand.emptyLive {
                Text(empty).font(.callout).foregroundStyle(.secondary)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(live) { entry in
                if case let .live(fact, actionTitle, _) = entry.kind {
                    HStack(spacing: 10) {
                        SetupIconTile(symbol: entry.symbol ?? "clock", size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).font(.headline).lineLimit(1)
                            Text(fact).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if let actionTitle {
                            Button(actionTitle) { model.run(entry) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                    .onTapGesture { model.open(entry) }
                }
            }
        }
    }

    /// A feature that can't run yet: the reason, and the one click that fixes it, on an orange card.
    private func warningCard(_ entry: StatusMenuEntry) -> some View {
        HStack(spacing: 10) {
            SetupIconTile(symbol: "exclamationmark.triangle.fill", tint: .orange, size: Metric.tile)
            Text(entry.title).font(.callout.weight(.medium)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if case let .warning(actionTitle) = entry.kind, let actionTitle {
                Button(actionTitle) { model.run(entry) }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous).fill(Color.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
    }

    /// A titled list: its rows in a card (scrolling inside it once there are more than fit), or its
    /// empty line, then the commands that always show at the card's foot.
    private func groupCard(_ group: StatusMenuGroup) -> some View {
        card(group.title) {
            if group.rows.isEmpty, let empty = group.empty {
                Text(empty)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if CGFloat(group.rows.count) > Metric.visibleRows {
                ScrollView { rows(group.rows) }
                    .frame(height: Metric.visibleRows * Metric.row)
            } else {
                rows(group.rows)
            }
            if !group.actions.isEmpty {
                Divider()
                rows(group.actions)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton("Setup", symbol: "sparkles", key: nil, action: model.onSetup)
            footerButton("Quit", symbol: "power", key: "⌘Q", action: model.onQuit)
        }
        .controlSize(.large)
    }

    private func footerButton(_ title: String, symbol: String, key: String?,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).accessibilityHidden(true)
                Text(title)
                if let key { Text(key).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(title)
    }

    // MARK: - Cards and rows

    /// The app's one card: a small title, then a rounded, faintly filled panel holding the rows.
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0, content: content)
                .background(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous).fill(Color.primary.opacity(0.035)))
                .overlay(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
        }
    }

    /// Rows separated by hairlines that start under the text, past the icon.
    private func rows(_ entries: [StatusMenuEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().padding(.leading, 46) }
                row(entry)
            }
        }
    }

    @ViewBuilder private func row(_ entry: StatusMenuEntry) -> some View {
        switch entry.kind {
        case .section:
            Text(entry.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        case let .toggle(isOn, disabled, _):
            HStack(spacing: 10) {
                icon(entry, tint: .secondary)
                Text(entry.title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if let secondary = entry.secondary {
                    secondaryButton(entry, secondary, hovered: hoveredRow == entry.id)
                }
                switchControl(entry, isOn: isOn)
            }
            .padding(.horizontal, 10)
            .frame(height: Metric.row)
            .background(Color.primary.opacity(hoveredRow == entry.id ? 0.04 : 0))
            .onHover { hover(entry, $0) }
            .disabled(disabled)
        case let .choice(options, selected):
            HStack(spacing: 10) {
                icon(entry, tint: .secondary)
                Text(entry.title).lineLimit(1)
                Spacer(minLength: 4)
                Picker(entry.title, selection: Binding(get: { selected }, set: { model.pick(entry, index: $0) })) {
                    ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
                }
                .pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: Metric.row)
        case let .command(danger):
            commandRow(entry, danger: danger)
        case .live, .warning:
            EmptyView()
        }
    }

    /// A row you click: the whole line is the target and lights under the pointer. A command that adds
    /// something ("New preset…") is drawn in the accent, like the app's other primary actions. A
    /// second button (Edit) sits at the end.
    private func commandRow(_ entry: StatusMenuEntry, danger: Bool) -> some View {
        let hovered = hoveredRow == entry.id
        let adds = entry.symbol == "plus" && entry.boxes == nil
        return HStack(spacing: 0) {
            Button { model.run(entry) } label: {
                HStack(spacing: 10) {
                    icon(entry, tint: adds ? .accentColor : .secondary)
                    Text(entry.title).lineLimit(1).truncationMode(.tail)
                        .fontWeight(adds ? .medium : .regular)
                        .foregroundStyle(danger ? AnyShapeStyle(.red) : adds ? AnyShapeStyle(Color.accentColor)
                                         : AnyShapeStyle(.primary))
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let secondary = entry.secondary {
                secondaryButton(entry, secondary, hovered: hovered)
                    .padding(.trailing, 6)
            } else {
                Spacer().frame(width: 10)
            }
        }
        .frame(height: Metric.row)
        .background(Color.primary.opacity(hovered ? 0.06 : 0))
        .onHover { hover(entry, $0) }
    }

    private func hover(_ entry: StatusMenuEntry, _ inside: Bool) {
        hoveredRow = inside ? entry.id : (hoveredRow == entry.id ? nil : hoveredRow)
    }

    /// A row's second button (Edit): quiet until its row is under the pointer.
    private func secondaryButton(_ entry: StatusMenuEntry, _ secondary: (symbol: String, help: String, action: () -> Void),
                                 hovered: Bool) -> some View {
        Button { model.runSecondary(entry) } label: {
            Image(systemName: secondary.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(hovered ? 0.13 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(secondary.help)
        .accessibilityLabel("\(secondary.help) \(entry.title)")
    }

    /// The system switch, wired to the entry's own action so the registry stays the one source of state.
    private func switchControl(_ entry: StatusMenuEntry, isOn: Bool) -> some View {
        Toggle(entry.title, isOn: Binding(get: { isOn }, set: { _ in model.run(entry) }))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }

    /// A row's icon: a layout's or preset's own shape when it has one, else a tinted tile as setup uses.
    @ViewBuilder private func icon(_ entry: StatusMenuEntry, tint: Color) -> some View {
        if let boxes = entry.boxes {
            MacsPaneLayoutGlyph(boxes: boxes, size: CGSize(width: 26, height: 17))
                .frame(width: Metric.tile + 2, height: Metric.tile)
        } else {
            SetupIconTile(symbol: entry.symbol ?? "circle", tint: tint, size: Metric.tile)
                .frame(width: Metric.tile + 2)
        }
    }
}
#endif
