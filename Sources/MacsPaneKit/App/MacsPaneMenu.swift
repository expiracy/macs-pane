#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// The MacsPane dropdown (`StatusMenuView` under the menu-bar icon), and with it everything MacsPane
/// lets you change: there is no separate Settings window. The switch beside the name is snapping
/// itself; then any warning, Open at login and how long to hold a window on the notch before the picker opens, your presets (click to apply, pencil to edit,
/// trash to delete) and every layout with its switch for the notch picker. Long lists scroll in place,
/// and both lists can be dragged into the order you want by their grips. Presets and layouts are made,
/// changed and deleted in the box editor.
enum MacsPaneMenu {
    static let brand = StatusMenuBrand(name: "MacsPane", emptyLive: nil, togglesTitle: "General")

    static func content(_ model: MacsPaneModel) -> StatusMenuContent {
        var content = StatusMenuContent()
        content.primary = .toggle("Snap windows dragged to the top", symbol: "rectangle.3.group",
                                  isOn: model.config.snap.enabled, primary: true) { [weak model] in
            guard let model else { return }
            model.setSnapping(!model.config.snap.enabled)
        }
        if !model.isAuthorized {
            content.warnings.append(.warning("Snapping needs Accessibility", actionTitle: "Grant") { [weak model] in
                model?.requestAccess()
            })
        }
        content.toggles = [
            .toggle("Open at login", symbol: "power", isOn: LoginItem.isEnabled) {
                LoginItem.setEnabled(!LoginItem.isEnabled)
            },
            // How long a dragged window rests on the notch before the picker opens.
            .choice("Hold for", symbol: "timer",
                    options: MacsPaneConfig.dwellChoices.map(Self.seconds),
                    selected: model.config.dwellChoiceIndex) { [weak model] index in
                model?.setDwell(MacsPaneConfig.dwellChoices[index])
            },
        ]
        content.groups = [presetGroup(model), layoutGroup(model)]
        content.renaming = model.renaming
        return content
    }

    /// "New from current desktop…": a window with a plus, drawn in the accent like the other new rows.
    private static let desktopSymbol = "macwindow.badge.plus"

    /// "0.3s", "1s": a hold time as the menu writes it.
    static func seconds(_ ms: Int) -> String {
        ms % 1000 == 0 ? "\(ms / 1000)s" : String(format: "%.1fs", Double(ms) / 1000)
    }

    /// Click a preset to apply it; its pencil opens it in the editor. "New from current desktop…" saves
    /// the windows on this screen as one, apps and all, and names it in place; "New preset…" draws one.
    private static func presetGroup(_ model: MacsPaneModel) -> StatusMenuGroup {
        let rows = model.config.presets.map { preset in
            let slots = preset.slots.filter { !$0.isRemoved }
            var row = StatusMenuEntry.command(preset.name, symbol: "square.grid.2x2", key: "preset-\(preset.id)",
                                              boxes: slots.map(\.region),
                                              secondary: ("pencil", "Edit", { [weak model] in model?.editPreset(preset.id) }),
                                              trash: ("Delete \(preset.name)", { [weak model] in model?.deletePreset(preset.id) }),
                                              rename: { [weak model] in model?.finishRenaming("preset-\(preset.id)", to: $0) }) {
                [weak model] in model?.applyPreset(preset.id)
            }
            row.boxIcons = slots.map { slot in
                guard case let .app(bundleID) = slot.binding else { return nil }
                return SnapAppIcons.icon(bundleID: bundleID)
            }
            return row
        }
        let fromDesktop = StatusMenuEntry.command("New from current desktop…", symbol: desktopSymbol,
                                                  key: "preset-from-desktop", keepsOpen: true) { [weak model] in model?.newPresetFromDesktop() }
        let new = StatusMenuEntry.command("New preset…", symbol: "plus") { [weak model] in model?.newPreset() }
        return StatusMenuGroup(title: "Presets", rows: rows, actions: [fromDesktop, new],
                               empty: "None yet. A preset puts your apps back where you like them.",
                               move: { [weak model] in model?.movePreset(from: $0, to: $1) })
    }

    /// Every layout, built-in and your own, with its switch for the notch picker and a bin; your own
    /// also have a pencil to change them. "New from current desktop…" saves the windows on this screen as one and
    /// names it in place; "Draw a new layout…" starts an empty one.
    private static func layoutGroup(_ model: MacsPaneModel) -> StatusMenuGroup {
        let offered = model.config.windows.dragBarLayoutIDs
        let mine = Set(model.config.windows.layouts.map(\.id))
        let rows = model.config.windows.layoutCatalog.map { layout in
            StatusMenuEntry.toggle(layout.name, symbol: "rectangle.dashed", isOn: offered.contains(layout.id),
                                   key: "layout-\(layout.id)", boxes: layout.boxes,
                                   secondary: mine.contains(layout.id)
                                       ? ("pencil", "Edit", { [weak model] in model?.editLayout(layout.id) }) : nil,
                                   trash: ("Delete \(layout.name)", { [weak model] in model?.deleteLayout(layout.id) }),
                                   rename: { [weak model] in model?.finishRenaming("layout-\(layout.id)", to: $0) }) {
                [weak model] in model?.toggleBar(layout.id)
            }
        }
        let fromDesktop = StatusMenuEntry.command("New from current desktop…", symbol: desktopSymbol,
                                                  key: "layout-from-desktop", keepsOpen: true) { [weak model] in model?.newLayoutFromDesktop() }
        let new = StatusMenuEntry.command("Draw a new layout…", symbol: "plus") { [weak model] in model?.newLayout() }
        // Deleted built-ins are only set aside: this brings them back.
        let restore = model.config.windows.deletedBuiltIns.isEmpty ? [] : [
            StatusMenuEntry.command("Restore built-in layouts", symbol: "arrow.counterclockwise", keepsOpen: true) {
                [weak model] in model?.restoreBuiltInLayouts()
            },
        ]
        return StatusMenuGroup(title: "Layouts in the notch", rows: rows, actions: [fromDesktop, new] + restore,
                               move: { [weak model] in model?.moveLayout(from: $0, to: $1) })
    }
}
#endif
