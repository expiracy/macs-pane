#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// The MacsPane dropdown (`StatusMenuView` under the menu-bar icon), and with it everything MacsPane
/// lets you change: there is no separate Settings window. The switch beside the name is snapping
/// itself; then any warning, Open at login and how long to hold a window on the notch before the picker opens, your presets (click to apply, pencil to edit,
/// trash to delete), every layout with its switch for the notch picker, and every shortcut in one
/// list. Long lists scroll in place, and the presets and layouts can be dragged into the order you want by their grips. Presets and layouts are made,
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
        content.groups = [presetGroup(model), layoutGroup(model), shortcutGroup(model)]
        content.renaming = model.renaming
        return content
    }

    /// "From the current desktop": a window with a plus.
    private static let desktopSymbol = "macwindow.badge.plus"

    /// "0.3s", "1s": a hold time as the menu writes it.
    static func seconds(_ ms: Int) -> String {
        ms % 1000 == 0 ? "\(ms / 1000)s" : String(format: "%.1fs", Double(ms) / 1000)
    }

    /// Click a preset to apply it; its pencil opens it in the editor. "New preset" opens a menu of two
    /// ways to make one: from the current desktop saves the windows on this screen as one, apps and all,
    /// and names it in place; "Draw one…" opens the editor.
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
            // Only a shortcut that is on: one switched off does nothing from here.
            row.shortcut = model.config.activeShortcuts.first { $0.action == .preset(id: preset.id) }?.shortcut.displayName
            row.boxIcons = slots.map { slot in
                guard case let .app(bundleID) = slot.binding else { return nil }
                return SnapAppIcons.icon(bundleID: bundleID)
            }
            return row
        }
        let new = StatusMenuEntry.submenu("New preset", symbol: "plus", key: "preset-new", items: [
            .command("From the current desktop", symbol: desktopSymbol, key: "preset-from-desktop", keepsOpen: true) {
                [weak model] in model?.newPresetFromDesktop()
            },
            .command("Draw one…", symbol: "pencil.and.outline") { [weak model] in model?.newPreset() },
        ])
        return StatusMenuGroup(title: "Presets", rows: rows, actions: [new],
                               empty: "None yet. A preset puts your apps back where you like them.",
                               move: { [weak model] in model?.movePreset(from: $0, to: $1) })
    }

    /// Every shortcut in one place: what it runs, drawn as its preset or its layout with the box picked
    /// out, its keys and its switch. The pencil opens it in the editor; the bin takes the shortcut away.
    private static func shortcutGroup(_ model: MacsPaneModel) -> StatusMenuGroup {
        let config = model.config
        let rows = config.shortcutList.compactMap { assigned -> StatusMenuEntry? in
            let action = assigned.action
            let title: String
            let boxes: [SnapRegion]
            var highlighted: Int?
            var icons: [NSImage?] = []
            switch action {
            case .preset(let id):
                guard let preset = config.presets.first(where: { $0.id == id }) else { return nil }
                let slots = preset.slots.filter { !$0.isRemoved }
                title = preset.name
                boxes = slots.map(\.region)
                icons = slots.map { slot in
                    guard case let .app(bundleID) = slot.binding else { return nil }
                    return SnapAppIcons.icon(bundleID: bundleID)
                }
            case let .layoutBox(layoutID, box):
                guard let layout = config.windows.layoutCatalog.first(where: { $0.id == layoutID }) else { return nil }
                title = "\(layout.name), box \(box + 1)"
                boxes = layout.boxes
                highlighted = box
            }
            var row = StatusMenuEntry.toggle(title, symbol: "keyboard", isOn: assigned.isEnabled,
                                             key: "shortcut-\(assigned.shortcut.displayName)", boxes: boxes,
                                             secondary: ("pencil", "Edit", { [weak model] in model?.editShortcut(action) }),
                                             trash: ("Remove \(assigned.shortcut.displayName)", { [weak model] in
                                                 model?.removeShortcut(for: action)
                                             })) { [weak model] in model?.toggleShortcut(action) }
            row.shortcut = assigned.shortcut.displayName
            row.highlightedBox = highlighted
            row.boxIcons = icons
            return row
        }
        return StatusMenuGroup(title: "Shortcuts", rows: rows,
                               empty: "None yet. Give a layout's box or a preset one in its editor.")
    }

    /// Every layout, built-in and your own, alike: a pencil to change it, a bin and its switch for the
    /// notch picker. "New layout" opens a menu of two ways to make one: from the
    /// current desktop saves the windows on this screen as one and names it in place; "Draw one…" starts
    /// an empty one.
    private static func layoutGroup(_ model: MacsPaneModel) -> StatusMenuGroup {
        let offered = model.config.windows.dragBarLayoutIDs
        let rows = model.config.windows.layoutCatalog.map { layout in
            StatusMenuEntry.toggle(layout.name, symbol: "rectangle.dashed", isOn: offered.contains(layout.id),
                                   key: "layout-\(layout.id)", boxes: layout.boxes,
                                   secondary: ("pencil", "Edit", { [weak model] in model?.editLayout(layout.id) }),
                                   trash: ("Delete \(layout.name)", { [weak model] in model?.deleteLayout(layout.id) }),
                                   rename: { [weak model] in model?.finishRenaming("layout-\(layout.id)", to: $0) }) {
                [weak model] in model?.toggleBar(layout.id)
            }
        }
        let new = StatusMenuEntry.submenu("New layout", symbol: "plus", key: "layout-new", items: [
            .command("From the current desktop", symbol: desktopSymbol, key: "layout-from-desktop", keepsOpen: true) {
                [weak model] in model?.newLayoutFromDesktop()
            },
            .command("Draw one…", symbol: "pencil.and.outline") { [weak model] in model?.newLayout() },
        ])
        // Deleted built-ins are only set aside and edited ones kept beside: this brings the originals back.
        let restore = !model.config.canRestoreBuiltInLayouts ? [] : [
            StatusMenuEntry.command("Restore built-in layouts", symbol: "arrow.counterclockwise", keepsOpen: true) {
                [weak model] in model?.restoreBuiltInLayouts()
            },
        ]
        return StatusMenuGroup(title: "Layouts in the notch", rows: rows, actions: [new] + restore,
                               move: { [weak model] in model?.moveLayout(from: $0, to: $1) })
    }
}
#endif
