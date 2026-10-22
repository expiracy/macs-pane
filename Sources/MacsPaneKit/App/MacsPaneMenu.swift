#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// The MacsPane dropdown (`StatusMenuView` under the menu-bar icon), holding the settings that belong
/// in a menu — acting from the menu bar, kept to what someone reaches for. The switch beside the name is snapping
/// itself; a box shows the last change with its Undo; then any warning, Open at login, the presets to
/// apply, and the two "save what's on screen" commands. Renaming, deleting and choosing the drag
/// bar's layouts need room, so they live in Settings.
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
        if model.config.snap.enabled, model.notchPlusPlusAlsoSnaps {
            content.warnings.append(.warning("Notch++ snaps dragged windows too"))
        }
        content.toggles = [.toggle("Open at login", symbol: "power", isOn: LoginItem.isEnabled) {
            LoginItem.setEnabled(!LoginItem.isEnabled)
        }]
        content.commands = presetCommands(model) + layoutCommands(model)
        return content
    }

    private static func presetCommands(_ model: MacsPaneModel) -> [StatusMenuEntry] {
        let presets = model.config.presets.map { preset in
            StatusMenuEntry.command(preset.name, symbol: "square.grid.2x2") { [weak model] in
                model?.applyPreset(preset.id)
            }
        }
        let save = StatusMenuEntry.command("Save windows as a preset", symbol: "plus.square.on.square") { [weak model] in
            model?.savePresetFromDesktop()
        }
        return [.section("Presets")] + presets + [save]
    }

    private static func layoutCommands(_ model: MacsPaneModel) -> [StatusMenuEntry] {
        [.section("Layouts"),
         .command("Save windows as a layout", symbol: "rectangle.split.3x1") { [weak model] in
             model?.saveLayoutFromDesktop()
         }]
    }
}
#endif
