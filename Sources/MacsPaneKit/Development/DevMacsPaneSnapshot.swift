#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// `macspane --snapshot-macspane <dir>`: render MacsPane's production surfaces offscreen — the
/// dropdown (with and without a last change, light and dark), the drag target, the open picker and
/// Settings — over a seeded config in a temporary file. No status item, no monitors, no window moves.
enum DevMacsPaneSnapshot {
    @MainActor static func runIfRequested(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: "--snapshot-macspane"), flag + 1 < arguments.count else {
            return false
        }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        DispatchQueue.main.async { render(into: directory) }
        app.run()
        return true
    }

    @MainActor private static func render(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macspane-snapshot-\(UUID()).json")
        let store = MacsPaneConfigStore(url: url, seed: { seed })
        let model = MacsPaneModel(store: store)
        let host = MacsPaneSnapHost(config: seed, recents: RecentWindowsService())
        host.notchSize = CGSize(width: 185, height: 32)
        host.screenWidth = 1512
        host.dwellMs = 0

        let busy = StatusMenuModel(brand: MacsPaneMenu.brand) { busyContent(model) }
        let quiet = StatusMenuModel(brand: MacsPaneMenu.brand) { quietContent(model) }
        let setupShots: [(String, NSWindow)] = [false, true].flatMap { dark in
            MacsPaneSetupModel.Step.allCases.map { step in
                let setup = MacsPaneSetupModel(app: model)
                setup.step = step
                // Offscreen the window is never key; draw the controls as the front window shows them.
                let root = MacsPaneSetupView(model: setup).environment(\.controlActiveState, .key)
                return ("setup-\(step)\(dark ? "-dark" : "")",
                        window(NSHostingView(rootView: root), size: SetupShell<EmptyView>.size, dark: dark))
            }
        }
        let windows: [(String, NSWindow)] = setupShots + [
            ("menu-busy", menuWindow(StatusMenuView(model: busy), dark: false)),
            ("menu-busy-dark", menuWindow(StatusMenuView(model: busy), dark: true)),
            ("menu-quiet", menuWindow(StatusMenuView(model: quiet), dark: false)),
            ("settings", menuWindow(MacsPaneSettingsView(model: model), dark: false)),
            ("grant", menuWindow(PermissionGrantView(
                grant: .accessibility, appName: "MacsPane",
                appURL: URL(fileURLWithPath: "/Applications/MacsPane.app"),
                model: PermissionGrantModel(grant: .accessibility, isGranted: { false }, prompt: nil)), dark: false)),
        ]
        // The two notch shots show one live host at two moments, so each is written when it is taken.
        let notch = notchWindow(host)
        host.setWindowDragActive(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            for (name, window) in windows { write(window, to: directory.appendingPathComponent("\(name).png")) }
            write(notch, to: directory.appendingPathComponent("notch-target.png"))
            host.windowSnap.begin(visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944), suggestions: [])
            host.setPointerInside(true, at: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                write(notch, to: directory.appendingPathComponent("notch-picker.png"))
                try? FileManager.default.removeItem(at: url)
                exit(0)
            }
        }
    }

    /// `macspane --export-icon <dir>`: the app icon's faces (1024 px) and marks layer from the drawing
    /// code, for `scripts/dev/make_macspane_icon.sh`.
    @MainActor static func exportIconIfRequested(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: "--export-icon"), flag + 1 < arguments.count else { return false }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func write<V: View>(_ view: V, _ name: String, scale: CGFloat = 1) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
        }
        for (face, name) in [(ColorScheme.dark, "dark"), (.light, "light")] {
            write(MacsPaneLogo(size: 1024, iconCanvas: true, face: face), "icon-1024-\(name).png")
            write(MacsPaneLogo(size: 1024, face: face, marksOnly: true), "marks-\(name).png")
        }
        write(MacsPaneGlyph().frame(width: 18, height: 18).foregroundStyle(.black), "glyph-menu-bar@2x.png", scale: 2)
        return true
    }

    private static var seed: MacsPaneConfig {
        var config = MacsPaneConfig()
        let halves = WindowLayout.builtIns[0]
        var coding = WindowPresetBuilder.make(from: halves, name: "Coding")
        coding.slots[0].binding = .app(bundleID: "com.apple.Safari")
        config.presets = [coding, WindowPresetBuilder.make(from: WindowLayout.builtIns[3], name: "Writing with notes and mail")]
        config.windows.layouts = [WindowLayout(id: "mine", name: "Desk", boxes: [
            .custom(NormalizedRect(x: 0, y: 0, width: 0.6, height: 1)),
            .custom(NormalizedRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5)),
            .custom(NormalizedRect(x: 0.6, y: 0, width: 0.4, height: 0.5)),
        ])]
        config.windows.dragBarLayoutIDs = ["halves", "quarters", "mine", "fill"]
        return config
    }

    /// The real dropdown, with a fixed last change and the Accessibility warning in place of live state.
    private static func busyContent(_ model: MacsPaneModel) -> StatusMenuContent {
        var content = MacsPaneMenu.content(model)
        content.live = [.live("Coding applied", symbol: "square.grid.2x2", fact: "3 windows", actionTitle: "Undo") {}]
        content.warnings = [.warning("Snapping needs Accessibility", actionTitle: "Grant") {}]
        return content
    }

    private static func quietContent(_ model: MacsPaneModel) -> StatusMenuContent {
        var content = MacsPaneMenu.content(model)
        content.live = []
        content.warnings = []
        return content
    }

    @MainActor private static func notchWindow(_ host: MacsPaneSnapHost) -> NSWindow {
        let widest = host.layout(suggestions: MacsPaneSnapHost.maxSuggestions)
        let size = CGSize(width: widest.pickerSize.width + widest.wingWidth + 80, height: widest.pickerSize.height + 60)
        let root = MacsPaneNotchView(host: host)
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.55))
            .environment(\.colorScheme, .dark)
        return window(NSHostingView(rootView: root), size: size, dark: true)
    }

    /// The real dropdown sits on the menu material; offscreen, the window background stands in.
    @MainActor private static func menuWindow<Content: View>(_ content: Content, dark: Bool) -> NSWindow {
        let root = content
            .background(Color(nsColor: .windowBackgroundColor))
            .padding(24)
            .background(Color(white: dark ? 0.3 : 0.7))
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: root)
        return window(host, size: host.fittingSize, dark: dark)
    }

    @MainActor private static func window(_ host: NSView, size: CGSize, dark: Bool) -> NSWindow {
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        return window
    }

    @MainActor private static func write(_ window: NSWindow, to url: URL) {
        guard let host = window.contentView else { return }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
