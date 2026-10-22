#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// MacsPane: a window manager in the menu bar. The only thing at the notch is the
/// drag — a window dragged to the top opens the snap picker there; everything else is the menu-bar
/// dropdown and a small Settings window. One boot path, shared by `swift run macspane`
/// (`Sources/MacsPane/main.swift`) and the bundled app (`MacsPaneApp/main.swift`).
///
///   --smoke-test      Boot, then quit after ~1.5 s — a launch check.
///   --open-settings   Open Settings, let it render, then quit.
public enum MacsPaneApp {
    public static func run(arguments: [String] = CommandLine.arguments) {
        if MainActor.assumeIsolated({
            DevMacsPaneSnapshot.exportIconIfRequested(arguments: arguments)
                || DevMacsPaneSnapshot.runIfRequested(arguments: arguments)
        }) { return }
        let app = NSApplication.shared
        // `NSApplication.delegate` is weak; `run()` never returns, so this frame keeps it alive.
        let delegate = MacsPaneAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        if arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSLog("MacsPane: smoke-test OK — launched cleanly, shutting down")
                NSApp.terminate(nil)
            }
        }
        if arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { delegate.showSettings() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSLog("MacsPane: open-settings OK — settings rendered, shutting down")
                NSApp.terminate(nil)
            }
        }
        app.run()
    }
}

/// The composition root: the config file, the model, the drag-only notch, the menu-bar icon and
/// its dropdown, and Settings.
final class MacsPaneAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: MacsPaneModel?
    private var statusItem: NSStatusItem?
    private var menu: StatusMenuController?
    private var settingsWindow: NSWindow?
    private let setup = MacsPaneSetupController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store: MacsPaneConfigStore
        if let url = try? MacsPanePaths.configURL() {
            store = MacsPaneConfigStore(url: url, seed: MacsPaneModel.notchPlusPlusSeed)
        } else {
            // No Application Support: run on defaults rather than not at all (nothing will persist).
            store = MacsPaneConfigStore(url: FileManager.default.temporaryDirectory
                .appendingPathComponent("macspane-config.json"))
        }
        let model = MacsPaneModel(store: store)
        model.onShowSettings = { [weak self] in self?.showSettings() }
        model.onShowSetup = { [weak self, weak model] in
            guard let model else { return }
            self?.setup.show(app: model)
        }
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
        menuModel.onSettings = { [weak self] in
            self?.menu?.close()
            self?.showSettings()
        }
        menuModel.onQuit = { NSApp.terminate(nil) }
        menu = StatusMenuController(button: button, model: menuModel)
    }

    func showSettings() {
        guard let model else { return }
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: MacsPaneSettingsView(model: model))
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "MacsPane Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)   // a Dock icon while Settings is open, so it can take focus
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
#endif
