#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// The MacsPane dropdown (`StatusMenuView` under the menu-bar icon), and with it everything MacsPane
/// lets you change: there is no separate Settings window. The switch beside the name is snapping
/// itself; a box shows the last change with its Undo; then any warning, Open at login, your presets
/// (click to apply, pencil to edit) and every layout with its switch for the notch picker. Long lists
/// scroll in place, and both lists can be dragged into the order you want by their grips. Presets and
/// layouts are made, changed and deleted in the box editor.
enum MacsPaneMenu {
    static let brand = StatusMenuBrand(name: "MacsPane",
                                       liveTitle: "Last change", emptyLive: nil, togglesTitle: "General")

    static func content(_ model: MacsPaneModel) -> StatusMenuContent {
        var content = StatusMenuContent()
        content.primary = .toggle("Snap windows dragged to the top", symbol: "rectangle.3.group",
                                  isOn: model.config.snap.enabled, primary: true) { [weak model] in
            guard let model else { return }
            model.setSnapping(!model.config.snap.enabled)
        }
        if let last = model.currentLastAction {
            content.live = [.live(last.title, symbol: last.symbol, fact: last.fact,
                                  actionTitle: last.actionTitle, action: last.perform)]
        }
        if !model.isAuthorized {
            content.warnings.append(.warning("Snapping needs Accessibility", actionTitle: "Grant") { [weak model] in
                model?.requestAccess()
            })
        }
        content.toggles = [.toggle("Open at login", symbol: "power", isOn: LoginItem.isEnabled) {
            LoginItem.setEnabled(!LoginItem.isEnabled)
        }]
        content.groups = [presetGroup(model), layoutGroup(model)]
        return content
    }

    /// Click a preset to apply it; its pencil opens it in the editor. "New preset…" starts one from the
    /// windows on this screen.
    private static func presetGroup(_ model: MacsPaneModel) -> StatusMenuGroup {
        let rows = model.config.presets.map { preset in
            StatusMenuEntry.command(preset.name, symbol: "square.grid.2x2", key: "preset-\(preset.id)",
                                    boxes: preset.slots.filter { !$0.isRemoved }.map(\.region),
                                    secondary: ("pencil", "Edit", { [weak model] in model?.editPreset(preset.id) })) {
                [weak model] in model?.applyPreset(preset.id)
            }
        }
        let new = StatusMenuEntry.command("New preset…", symbol: "plus") { [weak model] in model?.newPreset() }
        return StatusMenuGroup(title: "Presets", rows: rows, actions: [new],
                               empty: "None yet. A preset puts your apps back where you like them.",
                               move: { [weak model] in model?.movePreset(from: $0, to: $1) })
    }

    /// Every layout, built-in and your own, with its switch for the notch picker. Your own have a pencil
    /// to change or delete them; "Draw a new layout…" starts an empty one.
    private static func layoutGroup(_ model: MacsPaneModel) -> StatusMenuGroup {
        let offered = model.config.windows.dragBarLayoutIDs
        let mine = Set(model.config.windows.layouts.map(\.id))
        let rows = model.config.windows.layoutCatalog.map { layout in
            StatusMenuEntry.toggle(layout.name, symbol: "rectangle.dashed", isOn: offered.contains(layout.id),
                                   key: "layout-\(layout.id)", boxes: layout.boxes,
                                   secondary: mine.contains(layout.id)
                                       ? ("pencil", "Edit", { [weak model] in model?.editLayout(layout.id) }) : nil) {
                [weak model] in model?.toggleBar(layout.id)
            }
        }
        let new = StatusMenuEntry.command("Draw a new layout…", symbol: "plus") { [weak model] in model?.newLayout() }
        return StatusMenuGroup(title: "Layouts in the notch", rows: rows, actions: [new],
                               move: { [weak model] in model?.moveLayout(from: $0, to: $1) })
    }
}
#endif
