#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// `macspane --snapshot-macspane <dir>`: render MacsPane's production surfaces offscreen, the
/// dropdown (with and without a last change, light and dark), the drag target, the open picker, setup,
/// the box editor and the prompts, over a seeded config in a temporary file. No status item, no monitors, no window moves.
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

    /// `macspane --snapshot-notch-open <dir>`: the notch going from the drag target to the open picker,
    /// one frame every 40ms, to judge the opening animation frame by frame.
    @MainActor static func recordOpenIfRequested(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: "--snapshot-notch-open"), flag + 1 < arguments.count else {
            return false
        }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        DispatchQueue.main.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let host = MacsPaneSnapHost(config: seed, recents: RecentWindowsService())
            host.notchSize = CGSize(width: 185, height: 32)
            host.screenWidth = 1512
            host.dwellMs = 0
            let notch = notchWindow(host)
            host.setWindowDragActive(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                host.windowSnap.begin(visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
                                      suggestions: sampleSuggestions)
                host.setPointerInside(true, at: nil)
                for frame in 0..<20 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(frame) * 0.04) {
                        write(notch, to: directory.appendingPathComponent(String(format: "open-%02d.png", frame)))
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
            }
        }
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
        // The first preset's trash clicked once: it asks before deleting.
        let asking = StatusMenuModel(brand: MacsPaneMenu.brand) { busyContent(model) }
        asking.confirmingTrash = model.config.presets.first.map { "preset-\($0.id)" }
        // The last preset just saved from the desktop, its name being typed in place.
        let naming = StatusMenuModel(brand: MacsPaneMenu.brand) {
            var content = busyContent(model)
            content.renaming = model.config.presets.last.map { "preset-\($0.id)" }
            return content
        }
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
        // The practice notch open, a preset aimed at.
        let practice = MacsPaneSetupModel(app: model)
        practice.step = .drag
        practice.previewPicker = true
        let practiceShot = ("setup-drag-open", window(NSHostingView(rootView: MacsPaneSetupView(model: practice)
            .environment(\.controlActiveState, .key)), size: SetupShell<EmptyView>.size, dark: false))
        let windows: [(String, NSWindow)] = setupShots + editorShots(model) + [
            ("menu-busy", menuWindow(StatusMenuView(model: busy), dark: false)),
            ("menu-busy-dark", menuWindow(StatusMenuView(model: busy), dark: true)),
            ("menu-quiet", menuWindow(StatusMenuView(model: quiet), dark: false)),
            ("menu-delete", menuWindow(StatusMenuView(model: asking), dark: false)),
            ("menu-rename", menuWindow(StatusMenuView(model: naming), dark: false)),
            ("undo-activity", menuWindow(undoActivity(model), dark: true)),
            ("grant", menuWindow(PermissionDropdownView(
                grant: .accessibility, appName: "MacsPane",
                appURL: URL(fileURLWithPath: "/Applications/MacsPane.app"),
                model: PermissionGrantModel(grant: .accessibility, isGranted: { false }, prompt: nil)), dark: false)),
            ("grant-done", menuWindow(PermissionDropdownView(
                grant: .accessibility, appName: "MacsPane",
                appURL: URL(fileURLWithPath: "/Applications/MacsPane.app"),
                model: PermissionGrantModel(grant: .accessibility, isGranted: { true }, prompt: nil)), dark: true)),
        ]
        // The two notch shots show one live host at two moments, so each is written when it is taken.
        let notch = notchWindow(host)
        host.setWindowDragActive(true)
        host.setWindowOnTarget(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            for (name, window) in windows { write(window, to: directory.appendingPathComponent("\(name).png")) }
            write(notch, to: directory.appendingPathComponent("notch-target.png"))
            host.windowSnap.begin(visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944), suggestions: [])
            host.setPointerInside(true, at: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                write(notch, to: directory.appendingPathComponent("notch-picker.png"))
                // Written once its opening has settled.
                write(practiceShot.1, to: directory.appendingPathComponent("\(practiceShot.0).png"))
                // The same picker with the recent-app wing beside the layouts.
                host.windowSnap.begin(visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
                                      suggestions: sampleSuggestions)
                host.objectWillChange.send()   // the real drag sets these before the picker opens
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    write(notch, to: directory.appendingPathComponent("notch-picker-wing.png"))
                    // Aimed: the left box of the first layout, then the first preset.
                    let snap = host.windowSnap
                    if let first = snap.pickerLayouts.first, let inner = snap.layoutFrames[first.id]?.inner {
                        snap.pointerMoved(toPanelLocal: CGPoint(x: inner.minX + 4, y: inner.midY))
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        write(notch, to: directory.appendingPathComponent("notch-picker-aim-layout.png"))
                        if let tile = snap.presetFrames[0] { snap.pointerMoved(toPanelLocal: CGPoint(x: tile.midX, y: tile.midY)) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            write(notch, to: directory.appendingPathComponent("notch-picker-aim-preset.png"))
                            // One tile each side: the islands' titles loop rather than widen them.
                            snap.pointerMoved(toPanelLocal: .zero)
                            snap.begin(visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
                                       suggestions: Array(sampleSuggestions.prefix(1)))
                            snap.apply(presets: Array(seed.presets.prefix(1)))
                            host.objectWillChange.send()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                write(notch, to: directory.appendingPathComponent("notch-picker-one.png"))
                                try? FileManager.default.removeItem(at: url)
                                exit(0)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The box editor over a 14" screen: a preset with one app chosen and one box still empty and selected,
    /// a saved layout, and a new layout before anything is drawn.
    @MainActor private static func editorShots(_ model: MacsPaneModel) -> [(String, NSWindow)] {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        var preset = WindowBoxDraft(preset: seed.presets[0])
        preset.selection = preset.boxes.last?.id
        var layout = WindowBoxDraft(layout: seed.windows.layouts[0])
        layout.selection = layout.boxes.first?.id
        // Overlapping boxes: one behind the whole screen, two in front, the left one selected.
        var stacked = WindowBoxDraft(kind: .layout, name: "Focus")
        stacked.draw(from: CGPoint(x: 0.04, y: 0.1), to: CGPoint(x: 0.56, y: 0.92), grid: false)
        stacked.draw(from: CGPoint(x: 0.62, y: 0.1), to: CGPoint(x: 0.95, y: 0.7), grid: false)
        stacked.draw(from: .zero, to: CGPoint(x: 1, y: 1), grid: false)
        stacked.selection = stacked.boxes.first?.id
        let drafts: [(String, WindowBoxDraft, Bool)] = [("editor-layers", stacked, false),
                                                       ("editor-preset", preset, false),
                                                       ("editor-layout", layout, false),
                                                       ("editor-layout-delete", layout, false),
                                                       ("editor-new-layout", WindowBoxDraft(kind: .layout), true),
                                                       ("editor-preset-dark", preset, true)]
        // The layers menu for a preset over two layers, the back one hidden.
        var research = WindowBoxDraft(kind: .preset, name: "Research")
        research.draw(from: CGPoint(x: 0.04, y: 0.1), to: CGPoint(x: 0.56, y: 0.92), grid: false)
        research.draw(from: CGPoint(x: 0.62, y: 0.1), to: CGPoint(x: 0.95, y: 0.7), grid: false)
        research.draw(from: .zero, to: CGPoint(x: 1, y: 1), grid: false)
        for (box, app) in zip(research.boxes, ["com.apple.Safari", "com.apple.mail", "com.apple.Notes"]) {
            research.bind(.app(bundleID: app), to: box.id)
        }
        let layersModel = BoxEditorModel(draft: research, app: model, screen: nil)
        layersModel.setLayer(1, shown: false)
        let layersMenu = ("editor-layers-menu", window(NSHostingView(rootView: BoxLayersMenu(model: layersModel)
            .background(Color(nsColor: .windowBackgroundColor))), size: CGSize(width: 300, height: 200), dark: false))
        return [layersMenu] + drafts.map { name, draft, dark in
            let editor = BoxEditorModel(draft: draft, app: model, screen: nil)
            editor.confirmingDelete = name == "editor-layout-delete"   // its bin clicked once
            let root = ZStack {
                LinearGradient(colors: [Color(red: 0.36, green: 0.45, blue: 0.62), Color(red: 0.18, green: 0.2, blue: 0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                BoxEditorView(model: editor, screenFrame: screen, visibleFrame: visible)
            }
            .environment(\.controlActiveState, .key)
            return (name, window(NSHostingView(rootView: root), size: screen.size, dark: dark))
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

    /// The real dropdown, with the Accessibility warning in place of live state.
    private static func busyContent(_ model: MacsPaneModel) -> StatusMenuContent {
        var content = MacsPaneMenu.content(model)
        content.warnings = [.warning("Snapping needs Accessibility", actionTitle: "Grant") {}]
        return content
    }

    private static func quietContent(_ model: MacsPaneModel) -> StatusMenuContent {
        var content = MacsPaneMenu.content(model)
        content.warnings = []
        return content
    }

    @MainActor private static func notchWindow(_ host: MacsPaneSnapHost) -> NSWindow {
        let widest = host.layout(suggestions: MacsPaneSnapHost.maxSuggestions, presets: WindowSnapMetrics.maxPresets)
        let size = CGSize(width: widest.footprint.width + 80, height: widest.footprint.height + 60)
        let root = MacsPaneNotchView(host: host)
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.55))
            .environment(\.colorScheme, .dark)
        return window(NSHostingView(rootView: root), size: size, dark: true)
    }

    /// The notch's Undo activity, open, for the "Coding" preset: its two halves on the widened notch, as
    /// they settle (the live one is Core Animation layers, which an offscreen snapshot cannot draw).
    @MainActor private static func undoActivity(_ model: MacsPaneModel) -> some View {
        let m = EnvironmentValues().notchMetrics
        let width = 185 + 2 * UndoPromptController.wing
        return HStack(spacing: 0) {
            UndoActivityTitle(title: "Coding applied", symbol: "square.grid.2x2",
                              glyph: ResolvedPickerPreset(seed.presets[0]).boxes)
            Spacer(minLength: 185 + 16)
            UndoActivityButton {}.fixedSize()
        }
        .padding(.horizontal, SnapHeading.inset(fromCorner: m.rootTopRadiusCompact))
        .frame(width: width, height: 32)
        .background(NotchShape(topCornerRadius: m.rootTopRadiusCompact,
                               bottomCornerRadius: m.rootBottomRadiusCompact).fill(Color.black))
        .padding(.horizontal, 60 + UndoPromptController.overshoot)
        .padding(.bottom, 30)
        .background(Color(white: 0.55))
    }

    /// Two recent-app pairings, as the wing shows them: a pair side by side and a trio.
    @MainActor private static var sampleSuggestions: [ResolvedDragSuggestion] {
        func window(_ id: UInt32) -> ProcessWindowInfo {
            ProcessWindowInfo(id: id, ownerPid: Int32(id), title: nil, frame: .zero, isOnScreen: true, layer: 0, alpha: 1)
        }
        func icon(_ app: String) -> NSImage { NSWorkspace.shared.icon(forFile: "/System/Applications/\(app).app") }
        let pair = DragPairing(placements: [
            WindowTilePlacement(window: window(1), frame: CGRect(x: 0, y: 0, width: 756, height: 944)),
            WindowTilePlacement(window: window(2), frame: CGRect(x: 756, y: 0, width: 756, height: 944)),
        ])
        let trio = DragPairing(placements: [
            WindowTilePlacement(window: window(1), frame: CGRect(x: 0, y: 0, width: 756, height: 944)),
            WindowTilePlacement(window: window(2), frame: CGRect(x: 756, y: 472, width: 756, height: 472)),
            WindowTilePlacement(window: window(3), frame: CGRect(x: 756, y: 0, width: 756, height: 472)),
        ])
        return [ResolvedDragSuggestion(pairing: pair, icons: [icon("Notes"), icon("Mail")], label: "Notes + Mail"),
                ResolvedDragSuggestion(pairing: trio, icons: [icon("Notes"), icon("Mail"), icon("Calendar")],
                                       label: "Notes + Mail + Calendar")]
    }

    /// The real dropdown sits on the menu material; offscreen, the window background stands in.
    @MainActor private static func menuWindow<Content: View>(_ content: Content, dark: Bool) -> NSWindow {
        // Each view draws its own background (the bubbles their own shape), so none is added here.
        let root = content
            .padding(24)
            .background(Color(white: dark ? 0.3 : 0.7))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.controlActiveState, .key)   // the real dropdown is the key window
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
