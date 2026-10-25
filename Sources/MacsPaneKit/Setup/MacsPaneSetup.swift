#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// MacsPane's first-time setup: the setup shell with six steps: what it does (the notch at work), the drag
/// on sample windows, Accessibility (then the drag on a real window), which layouts the notch offers,
/// suggested shortcuts tried on sample windows, and where MacsPane lives in the menu bar. Shown on a
/// first run and from the dropdown's Setup button.
final class MacsPaneSetupModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, drag, access, layouts, shortcuts, menuBar }

    @Published var step: Step = .welcome {
        didSet { shortcuts.setActive(step == .shortcuts) }
    }
    /// Offscreen-render seed only: the practice notch open with a preset aimed at.
    var previewPicker = false
    @Published private(set) var authorized: Bool
    /// Grant Access was clicked, so System Settings is open at the list.
    @Published private(set) var grantClicked = false
    let app: MacsPaneModel
    let shortcuts: SetupShortcutsModel
    var onFinish: (() -> Void)?
    /// Opens the real dropdown under the real menu-bar icon (the last step's Show me).
    var onShowMenu: (() -> Void)?
    private var poll: Timer?
    /// The notch's snaps before setup opened: one more is a real window dragged there.
    private let snapsAtStart: Int

    init(app: MacsPaneModel) {
        self.app = app
        shortcuts = SetupShortcutsModel(app: app)
        authorized = app.isAuthorized
        snapsAtStart = app.windowSnaps
        // The grant happens in System Settings; read it back each second so the step updates by itself.
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.authorized != self.app.isAuthorized else { return }
            self.authorized = self.app.isAuthorized
        }
    }

    deinit { poll?.invalidate() }

    /// A real window has been snapped from the notch since setup opened.
    var triedForReal: Bool { app.windowSnaps > snapsAtStart }

    func grant() {
        grantClicked = true
        app.requestAccess()
    }

    func showMenu() { onShowMenu?() }

    func finish() {
        close()
        app.completeSetup()
        onFinish?()
    }

    /// The window is going: stop listening for the grant and give the shortcuts back to every app.
    func close() {
        poll?.invalidate()
        shortcuts.setActive(false)
    }
}

struct MacsPaneSetupView: View {
    @ObservedObject var model: MacsPaneSetupModel
    @ObservedObject var app: MacsPaneModel

    init(model: MacsPaneSetupModel) {
        self.model = model
        self.app = model.app
    }

    var body: some View {
        SetupShell(appName: "MacsPane",
                   steps: MacsPaneSetupModel.Step.allCases.map(\.shellStep),
                   current: Binding(get: { model.step.rawValue },
                                    set: { model.step = MacsPaneSetupModel.Step(rawValue: $0) ?? .welcome }),
                   finishTitle: "Start using MacsPane",
                   footnote: "You can change all of this later from the menu bar.",
                   onFinish: model.finish) {
            switch model.step {
            case .welcome: welcome
            case .drag: drag
            case .access: access
            case .layouts: layouts
            case .shortcuts: SetupShortcutsStep(model: model.shortcuts)
            case .menuBar: menuBar
            }
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            SetupWelcomeDemo(config: app.config)
            HStack(alignment: .top, spacing: 12) {
                feature("rectangle.split.2x1", "Drag to the notch",
                        "Hold a window on the notch and your layouts open. Let go on a box and the window fills it.")
                feature("square.stack.3d.up", "Presets",
                        "Arrange your windows once, save them as a preset, and put them all back with one click.")
                feature("keyboard", "Shortcuts",
                        "Give a box keys, like \(rightHalfKeys), and send the window you're in there from any app.")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The right half's keys as you have them, or as setup suggests them.
    private var rightHalfKeys: String {
        let config = app.config
        return config.shortcutSuggestions.first { $0.name == "Right half" }.map { config.keys(for: $0).displayName } ?? "⌃⌥→"
    }

    private var drag: some View {
        FirstRunSnapDemo(config: app.config, previewPicker: model.previewPicker,
                         dwellIndex: Binding(get: { app.config.dwellChoiceIndex },
                                             set: { app.setDwell(MacsPaneConfig.dwellChoices[$0]) }))
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 12) {
            SetupIntroRow(text: model.authorized ? "Accessibility is on: MacsPane can move your windows."
                                                 : "MacsPane moves other apps' windows through Accessibility. It reads nothing else.") {
                if model.authorized {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button("Grant Access") { model.grant() }
                        .buttonStyle(.borderedProminent)
                }
            }
            SetupAccessPicture(granted: model.authorized)
            HStack(alignment: .top, spacing: 18) {
                SetupLessonStep(title: "Click Grant Access", detail: "System Settings opens at this list.",
                                done: model.grantClicked || model.authorized)
                SetupLessonStep(title: "Switch MacsPane on",
                                detail: "If it isn't in the list, drag it in from the box under the window.",
                                done: model.authorized)
                SetupLessonStep(title: "Try it on a real window",
                                detail: "Drag any app's window by its title bar to the notch and let go on a box.",
                                done: model.triedForReal)
            }
            Text(accessStatus).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var accessStatus: String {
        if model.triedForReal { return "That was a real window: MacsPane is working." }
        if model.authorized {
            return "You can turn it off any time in System Settings › Privacy & Security › Accessibility."
        }
        return "Until it's on, dragging a window to the notch does nothing. This step notices as soon as it's on."
    }

    private var layouts: some View {
        let offered = app.config.windows.dragBarLayoutIDs
        let catalog = app.config.windows.layoutCatalog
        return VStack(alignment: .leading, spacing: 12) {
            SetupIntroRow(text: "Click a layout to add it to the notch or take it out.") {
                // Brings back the built-ins you deleted or changed; your changes stay as your own.
                Button("Restore built-in layouts") { app.restoreBuiltInLayouts() }
                    .disabled(!app.config.canRestoreBuiltInLayouts)
                    .help(app.config.canRestoreBuiltInLayouts
                          ? "Bring back the built-in layouts as they first were. Layouts you changed stay, as your own."
                          : "Every built-in layout is here as it first was")
                Text(offered.count == 1 ? "1 in the notch" : "\(offered.count) in the notch")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .contentTransition(.numericText())
            }
            SetupLayoutsPreview(config: app.config)
            // A long catalogue scrolls sideways rather than pushing the line under it off.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(catalog) { layoutCard($0, on: offered.contains($0.id)) }
                }
                .padding(1)
            }
            Text(layoutsStatus(catalog.filter { offered.contains($0.id) }.map(\.name)))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func layoutsStatus(_ names: [String]) -> String {
        names.isEmpty ? "Nothing is in the notch yet: pick at least one layout."
                      : "The notch offers \(ListFormatter.localizedString(byJoining: names)), in the menu's order."
    }

    private var menuBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            SetupIntroRow(text: "Everything MacsPane does starts from its icon, up by the clock.") {
                Button("Show me") { model.showMenu() }
                    .buttonStyle(.borderedProminent)
                    .help("Open the MacsPane menu under its icon")
            }
            SetupMenuBarPicture(app: app)
            HStack(alignment: .top, spacing: 14) {
                menuPoint("square.grid.2x2", "Presets", "Apply one, save your desktop as one, or draw one.")
                menuPoint("rectangle.split.2x1", "Layouts", "Choose which the notch offers, or draw your own.")
                menuPoint("keyboard", "Shortcuts", "See every one, switch them off, or change their keys.")
                menuPoint("gearshape", "Settings", "How long to hold, and this setup again.")
            }
            SetupCard(padding: 10) {
                Toggle(isOn: Binding(get: { LoginItem.isEnabled },
                                     set: { LoginItem.setEnabled($0); app.objectWillChange.send() })) {
                    HStack(spacing: 10) {
                        SetupIconTile(symbol: "power", tint: .secondary, size: 24)
                        Text("Open MacsPane at login").font(.callout.weight(.semibold))
                        Text("So the notch is ready whenever you are.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    private func menuPoint(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// A layout as a small card you tick: its shape, its name, and whether the notch offers it.
    private func layoutCard(_ layout: WindowLayout, on: Bool) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { app.toggleBar(layout.id) } } label: {
            VStack(spacing: 6) {
                MacsPaneLayoutGlyph(boxes: layout.boxes, size: CGSize(width: 56, height: 35))
                    .opacity(on ? 1 : 0.55)
                Text(layout.name)
                    .font(.caption.weight(on ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.top, 12).padding(.bottom, 8).padding(.horizontal, 8)
            .frame(width: 88)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(on ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: on ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
                    .padding(5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? "In the notch · click to take it out" : "Not in the notch · click to add it")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        SetupCard {
            VStack(alignment: .leading, spacing: 10) {
                SetupIconTile(symbol: symbol)
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// The welcome step's picture: the app's own notch at work, on a loop. A cursor drags Safari to the
/// notch, the strip appears, the layouts open, and it lets go on the left box of a layout; then it
/// rests on Notes and the right half's keys send Notes to the right half. Then the windows scatter and
/// it plays again. Runs only while it is on screen.
private struct SetupWelcomeDemo: View {
    @StateObject private var driver: SetupNotchDriver
    @State private var cursor: CGPoint?
    /// The keys being pressed, drawn over the desk.
    @State private var keys: KeyShortcut?
    private let rightHalf: KeyShortcut
    /// The demo's own hold time, so it doesn't drag on a long one.
    private static let dwellMs = 450

    init(config: MacsPaneConfig) {
        _driver = StateObject(wrappedValue: SetupNotchDriver(config: config, dwellMs: Self.dwellMs))
        rightHalf = config.shortcutSuggestions.first { $0.name == "Right half" }.map(config.keys(for:))
            ?? KeyShortcut(keyCode: 124, modifiers: [.control, .option])
    }

    var body: some View {
        SetupWelcomeDesktop(host: driver.host) {
            GeometryReader { geo in
                SetupNotchStage(driver: driver, size: geo.size, interactive: false, cursor: cursor)
                    .task(id: geo.size) { await play(in: geo.size) }
            }
        }
        .overlay(alignment: .bottom) {
            if let keys {
                SetupKeyCaps(shortcut: keys)
                    .padding(.bottom, 18)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A window dragged to the notch opens your layouts, and letting go on a box snaps it there. "
                            + "A shortcut sends another window to a box.")
    }

    @MainActor private func play(in size: CGSize) async {
        let screen = SetupNotchDriver.screen(in: size)
        let lesson = driver.lesson
        cursor = CGPoint(x: size.width * 0.5, y: size.height * 0.8)
        while !Task.isCancelled {
            lesson.scatter()
            await pause(0.8)
            // Safari by the drag, into the left box of a layout.
            if let window = lesson.windows.first(where: { $0.app == WindowsLessonModel.apps[0] }) {
                let rect = driver.frame(of: window, in: screen)
                let titleBar = CGPoint(x: rect.midX, y: rect.minY + 8)
                await glide(to: titleBar, over: 0.6)
                await pause(0.2)
                driver.begin(window, at: titleBar, in: screen)
                await glide(to: CGPoint(x: size.width / 2, y: 14), over: 0.8, dragging: true)
                // The strip, then the layouts once the hold is up.
                await pause(Double(Self.dwellMs) / 1000 + 0.7)
                if let target = boxPoint(0) {
                    await glide(to: target, over: 0.6, dragging: true)
                    await pause(0.7)
                }
                driver.end(in: screen)
                await pause(0.9)
            }
            // Notes by its keys, into the right half.
            if let window = lesson.windows.first(where: { $0.app == WindowsLessonModel.apps[2] }) {
                let rect = driver.frame(of: window, in: screen)
                await glide(to: CGPoint(x: rect.midX, y: rect.midY + 20), over: 0.6)
                await pause(0.4)
                withAnimation(.bouncy(duration: 0.25)) { keys = rightHalf }
                await pause(0.35)
                withAnimation(NotchMotion.land) {
                    lesson.place(window.app, at: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
                }
                await pause(1.1)
                withAnimation(.easeOut(duration: 0.2)) { keys = nil }
            }
            await pause(1.8)
        }
    }

    /// The middle of box `index` of the first offered layout with two boxes, as the open notch draws it.
    @MainActor private func boxPoint(_ index: Int) -> CGPoint? {
        let snap = driver.host.windowSnap
        guard let layout = snap.pickerLayouts.first(where: { $0.boxes.count >= 2 }) ?? snap.pickerLayouts.first,
              let inner = snap.layoutFrames[layout.id]?.inner else { return nil }
        let unit = WindowsLessonModel.topLeft(layout.boxes[min(index, layout.boxes.count - 1)])
        return CGPoint(x: inner.minX + unit.midX * inner.width, y: inner.minY + unit.midY * inner.height)
    }

    /// Move the cursor to `point`, easing in and out, carrying the window when `dragging`.
    @MainActor private func glide(to point: CGPoint, over duration: Double, dragging: Bool = false) async {
        let start = cursor ?? point
        let frames = max(1, Int(duration * 60))
        for frame in 1...frames {
            guard !Task.isCancelled else { return }
            let t = Double(frame) / Double(frames)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let next = CGPoint(x: start.x + (point.x - start.x) * eased, y: start.y + (point.y - start.y) * eased)
            cursor = next
            if dragging { driver.move(to: next) }
            try? await Task.sleep(nanoseconds: 16_666_667)
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

/// The last step's picture: the menu bar with MacsPane's icon ringed, and its real menu hanging from it,
/// as clicking the icon shows it.
private struct SetupMenuBarPicture: View {
    @StateObject private var menu: StatusMenuModel
    @State private var pulse = false
    @Environment(\.colorScheme) private var scheme
    /// The menu drawn smaller, so its top half fits the picture.
    private static let scale: CGFloat = 0.62
    /// Where the bubble's nub sits along its top, near its right end, so the menu hangs left of the icon.
    private static let nubX: CGFloat = 270

    init(app: MacsPaneModel) {
        _menu = StateObject(wrappedValue: StatusMenuModel(brand: MacsPaneMenu.brand) { [weak app] in
            app.map(MacsPaneMenu.content) ?? StatusMenuContent()
        })
    }

    var body: some View {
        SetupDesktop(height: SetupStage.height) {
            GeometryReader { geo in
                // Left of the Wi-Fi and the clock, where a new menu-bar icon lands.
                let icon = CGPoint(x: geo.size.width - 96, y: NotchGeometry.standardNotchSize.height / 2)
                ZStack(alignment: .topLeading) {
                    SetupRestingNotch()
                    StatusMenuView(model: menu)
                        .fixedSize()
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.36),
                                                     .init(color: .clear, location: 0.46)],
                                             startPoint: .top, endPoint: .bottom))
                        .scaleEffect(Self.scale, anchor: .topLeading)
                        .offset(x: icon.x - Self.nubX * Self.scale, y: icon.y + 12)
                        .environment(\.colorScheme, scheme)
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: 30, height: 30)
                        .scaleEffect(pulse ? 1.5 : 1)
                        .opacity(pulse ? 0 : 0.9)
                        .position(icon)
                    MacsPaneGlyph()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.accentColor.opacity(0.28)))
                        .position(icon)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            menu.nubX = Self.nubX
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The MacsPane icon in the menu bar, with its menu open below it.")
    }
}

/// The desk the welcome demo plays on, its menu bar words hidden while the notch is out over them.
private struct SetupWelcomeDesktop<Content: View>: View {
    @ObservedObject var host: MacsPaneSnapHost
    @ViewBuilder var content: () -> Content

    var body: some View {
        SetupDesktop(height: SetupStage.height, showsMenuItems: host.stage == .rest, notch: content)
    }
}

extension MacsPaneSetupModel.Step {
    var shellStep: SetupShellStep {
        switch self {
        case .welcome:
            SetupShellStep(title: "Welcome to MacsPane", subtitle: "Snap any window into place by dragging it to the notch.",
                           symbol: "hand.wave", shortTitle: "Welcome")
        case .drag:
            SetupShellStep(title: "Try the drag", subtitle: "The gesture you'll use on every window, practised on samples.",
                           symbol: "rectangle.split.2x1")
        case .access:
            SetupShellStep(title: "Allow Accessibility",
                           subtitle: "The one permission MacsPane needs to move your real windows.",
                           symbol: "lock.shield")
        case .layouts:
            SetupShellStep(title: "Choose your layouts",
                           subtitle: "The notch offers these when you hold a window on it.",
                           symbol: "square.grid.2x2", shortTitle: "Layouts")
        case .shortcuts:
            SetupShellStep(title: "Keys for your windows",
                           subtitle: "Send the window you're in to a box without reaching for the mouse.",
                           symbol: "keyboard", shortTitle: "Shortcuts")
        case .menuBar:
            SetupShellStep(title: "Find it in the menu bar",
                           subtitle: "MacsPane has no window of its own: click its icon for everything it does.",
                           symbol: "menubar.arrow.up.rectangle", shortTitle: "Menu bar")
        }
    }
}

/// Opens the setup window and puts the app back to menu-bar-only when it closes. Closing it counts as
/// done; the dropdown's Setup button brings it back.
final class MacsPaneSetupController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// Opens the real dropdown, for the last step's Show me.
    var onShowMenu: (() -> Void)?

    func show(app: MacsPaneModel) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let model = MacsPaneSetupModel(app: app)
        self.model = model
        model.onFinish = { [weak self] in self?.window?.close() }
        model.onShowMenu = { [weak self] in self?.onShowMenu?() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: MacsPaneSetupView(model: model)))
        window.title = "Set up MacsPane"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(SetupShell<EmptyView>.size)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        onClose = { app.completeSetup() }
    }

    private var onClose: (() -> Void)?
    private var model: MacsPaneSetupModel?

    func windowWillClose(_ notification: Notification) {
        model?.close()
        model = nil
        onClose?()
        onClose = nil
        window = nil
        if !NSApp.windows.contains(where: { $0.isVisible && $0 !== notification.object as? NSWindow && $0.canBecomeKey }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
#endif
