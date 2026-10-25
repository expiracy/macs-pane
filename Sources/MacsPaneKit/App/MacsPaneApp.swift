#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// MacsPane: a window manager in the menu bar. The only thing at the notch is the
/// drag, a window dragged to the top opens the snap picker there; everything else is the menu-bar
/// dropdown, which holds every setting. One boot path, shared by `swift run macspane`
/// (`Sources/MacsPane/main.swift`) and the bundled app (`MacsPaneApp/main.swift`).
///
///   --smoke-test      Boot, then quit after ~1.5 s, a launch check.
///   --open-editor     Open the box editor on a new preset, to try drawing without the menu.
public enum MacsPaneApp {
    public static func run(arguments: [String] = CommandLine.arguments) {
        if MainActor.assumeIsolated({
            DevMacsPaneSnapshot.exportIconIfRequested(arguments: arguments)
                || DevMacsPaneSnapshot.runIfRequested(arguments: arguments)
                || DevMacsPaneSnapshot.recordOpenIfRequested(arguments: arguments)
        }) { return }
        let app = NSApplication.shared
        // `NSApplication.delegate` is weak; `run()` never returns, so this frame keeps it alive.
        let delegate = MacsPaneAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        if arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSLog("MacsPane: smoke-test OK: launched cleanly, shutting down")
                NSApp.terminate(nil)
            }
        }
        if arguments.contains("--open-editor") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { delegate.openEditor() }
        }
        app.run()
    }
}

/// The composition root: the config file, the model, the drag-only notch, the menu-bar icon and
/// its dropdown, the box editor and setup.
final class MacsPaneAppDelegate: NSObject, NSApplicationDelegate {
    private var model: MacsPaneModel?
    private var statusItem: NSStatusItem?
    private var menu: StatusMenuController?
    private let setup = MacsPaneSetupController()
    private let editor = BoxEditorController()
    private let undoPrompt = UndoPromptController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store: MacsPaneConfigStore
        if let url = try? MacsPanePaths.configURL() {
            store = MacsPaneConfigStore(url: url)
        } else {
            // No Application Support: run on defaults rather than not at all (nothing will persist).
            store = MacsPaneConfigStore(url: FileManager.default.temporaryDirectory
                .appendingPathComponent("macspane-config.json"))
        }
        let model = MacsPaneModel(store: store)
        model.onShowSetup = { [weak self, weak model] in
            guard let model else { return }
            self?.setup.show(app: model)
        }
        model.onEdit = { [weak self, weak model] draft in
            guard let model else { return }
            self?.editor.show(draft, app: model)
        }
        model.onUndoPrompt = { [weak self, weak model] action in
            self?.undoPrompt.show(title: action.title, symbol: action.symbol, glyph: action.glyph,
                                  on: MacsPaneModel.pointerScreen) { done in
                guard let model else { return done() }
                model.perform(action, done: done)
            }
        }
        undoPrompt.prepare()
        // A new window drag needs the notch: the Undo activity steps out of its way.
        model.notch.host.onWindowDragStart = { [weak self] in self?.undoPrompt.close() }
        self.model = model
        installStatusItem(model)
        model.start()
        // The setup window asks for Accessibility in its own step; afterwards the dropdown's warning
        // carries the Grant button.
        if !store.config.setupCompleted { setup.show(app: model) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    private func installStatusItem(_ model: MacsPaneModel) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let button = item.button else { return }
        button.image = MacsPaneGlyph.templateImage()
        button.toolTip = "MacsPane"
        let menuModel = StatusMenuModel(brand: MacsPaneMenu.brand) { [weak model] in
            model.map(MacsPaneMenu.content) ?? StatusMenuContent()
        }
        menuModel.onSetup = { [weak self, weak model] in
            self?.menu?.close()
            guard let model else { return }
            self?.setup.show(app: model)
        }
        menuModel.onQuit = { NSApp.terminate(nil) }
        menu = StatusMenuController(button: button, model: menuModel)
        setup.onShowMenu = { [weak self] in self?.menu?.show() }
    }

    func openEditor() { model?.newPreset() }
}
#endif
