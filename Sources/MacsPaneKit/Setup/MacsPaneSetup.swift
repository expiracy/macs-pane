#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// MacsPane's first-time setup: the setup shell with five steps: what it does (the notch at work), Accessibility,
/// the drag on sample windows, which layouts the notch offers, and where MacsPane lives in the menu bar. Shown
/// on a first run and from the dropdown's Setup button.
final class MacsPaneSetupModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, access, drag, layouts, menuBar }

    @Published var step: Step = .welcome
    /// Offscreen-render seed only: the practice notch open with a preset aimed at.
    var previewPicker = false
    @Published private(set) var authorized: Bool
    let app: MacsPaneModel
    var onFinish: (() -> Void)?
    /// Opens the real dropdown under the real menu-bar icon (the last step's Show me).
    var onShowMenu: (() -> Void)?
    private var poll: Timer?

    init(app: MacsPaneModel) {
        self.app = app
        authorized = app.isAuthorized
        // The grant happens in System Settings; read it back each second so the step updates by itself.
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.authorized != self.app.isAuthorized else { return }
            self.authorized = self.app.isAuthorized
        }
    }

    deinit { poll?.invalidate() }

    func grant() { app.requestAccess() }

    func showMenu() { onShowMenu?() }

    func finish() {
        poll?.invalidate()
        app.completeSetup()
        onFinish?()
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
            case .access: access
            case .drag: drag
            case .layouts: layouts
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
                feature("square.stack.3d.up", "Save presets",
                        "Arrange your windows once, save them as a preset, and put them all back with one click.")
                feature("menubar.rectangle", "Lives in the menu bar",
                        "Your presets, layouts and settings sit under the MacsPane icon. Undo appears in the notch.")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 16) {
            SetupCard(padding: 20) {
                HStack(spacing: 16) {
                    SetupIconTile(symbol: "hand.raised.fill", size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility").font(.system(size: 15, weight: .semibold))
                        Text("Lets MacsPane move and resize other apps' windows. It reads nothing else.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    if model.authorized {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                    } else {
                        Button("Grant Access") { model.grant() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
            }
            if model.authorized {
                SetupCard {
                    Label {
                        Text("All set. Dragging a window to the notch now opens your layouts.")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                    .font(.callout)
                }
                Label("You can turn it off any time in System Settings › Privacy & Security › Accessibility.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                SetupCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to turn it on").font(.callout.weight(.semibold))
                        instruction(1, "Click Grant Access. System Settings opens at the Accessibility list.")
                        instruction(2, "Drag the MacsPane icon from the box under that window into the list, "
                                    + "or switch MacsPane on if it's already there.")
                        instruction(3, "Come back here. This step notices as soon as it's on.")
                    }
                }
                Label("Until it's on, dragging a window to the notch does nothing.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var drag: some View {
        FirstRunSnapDemo(config: app.config, previewPicker: model.previewPicker)
    }

    private var layouts: some View {
        let offered = app.config.windows.dragBarLayoutIDs
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Click a layout to add it to the notch or take it out.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                // Brings back the built-ins you deleted or changed; your changes stay as your own.
                Button("Restore built-in layouts") { app.restoreBuiltInLayouts() }
                    .controlSize(.small)
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
            // Saved layouts join the built-ins here, so a long catalogue scrolls instead of pushing the login row off.
            ViewThatFits(in: .vertical) {
                layoutGrid(offered)
                ScrollView { layoutGrid(offered) }
            }
            SetupCard(padding: 14) {
                Toggle(isOn: Binding(get: { LoginItem.isEnabled },
                                     set: { LoginItem.setEnabled($0); app.objectWillChange.send() })) {
                    HStack(spacing: 12) {
                        SetupIconTile(symbol: "power", tint: .secondary, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Open MacsPane at login").font(.callout.weight(.semibold))
                            Text("So the notch is ready whenever you are.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .toggleStyle(.switch)
            }
            // The same choice as the menu's Hold for.
            SetupCard(padding: 14) {
                HStack(spacing: 12) {
                    SetupIconTile(symbol: "timer", tint: .secondary, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hold for").font(.callout.weight(.semibold))
                        Text("How long a window rests on the notch before your layouts open.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Hold for", selection: Binding(get: { app.config.dwellChoiceIndex },
                                                          set: { app.setDwell(MacsPaneConfig.dwellChoices[$0]) })) {
                        ForEach(MacsPaneConfig.dwellChoices.indices, id: \.self) { index in
                            Text(MacsPaneMenu.seconds(MacsPaneConfig.dwellChoices[index])).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    private var menuBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            SetupIntroRow(text: "Everything MacsPane does starts from its icon, up by the clock.") {
                Button("Show me") { model.showMenu() }
                    .buttonStyle(.borderedProminent)
                    .help("Open the MacsPane menu under its icon")
            }
            SetupMenuBarPicture(app: app)
            HStack(alignment: .top, spacing: 18) {
                menuPoint("square.grid.2x2", "Presets", "Apply one with a click, save your desktop as one, or draw a new one.")
                menuPoint("rectangle.split.2x1", "Layouts", "Choose which the notch offers and in what order, or draw your own.")
                menuPoint("gearshape", "Settings", "How long to hold, opening at login, and this setup again.")
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

    private func layoutGrid(_ offered: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            ForEach(app.config.windows.layoutCatalog) { layout in
                layoutCard(layout, on: offered.contains(layout.id))
            }
        }
        .padding(1)
    }

    /// A layout as a card you tick: its shape, its name, and whether the picker offers it.
    private func layoutCard(_ layout: WindowLayout, on: Bool) -> some View {
        Button { app.toggleBar(layout.id) } label: {
            VStack(spacing: 10) {
                MacsPaneLayoutGlyph(boxes: layout.boxes, size: CGSize(width: 104, height: 64))
                    .opacity(on ? 1 : 0.55)
                Text(layout.name)
                    .font(.callout.weight(on ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.top, 18).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: on ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
                    .padding(8)
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

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.13)))
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The welcome step's picture: the app's own notch at work, on a loop. A cursor drags Safari to the
/// notch, the strip appears, the layouts open, and it lets go on the left box of a layout; then Notes
/// into the right box. Then the windows scatter and it plays again. Runs only while it is on screen.
private struct SetupWelcomeDemo: View {
    @StateObject private var driver: SetupNotchDriver
    @State private var cursor: CGPoint?
    /// The demo's own hold time, so it doesn't drag on a long one.
    private static let dwellMs = 450

    init(config: MacsPaneConfig) {
        _driver = StateObject(wrappedValue: SetupNotchDriver(config: config, dwellMs: Self.dwellMs))
    }

    var body: some View {
        SetupWelcomeDesktop(host: driver.host) {
            GeometryReader { geo in
                SetupNotchStage(driver: driver, size: geo.size, interactive: false, cursor: cursor)
                    .task(id: geo.size) { await play(in: geo.size) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A window dragged to the notch opens your layouts, and letting go on a box snaps it there.")
    }

    @MainActor private func play(in size: CGSize) async {
        let screen = SetupNotchDriver.screen(in: size)
        let lesson = driver.lesson
        cursor = CGPoint(x: size.width * 0.5, y: size.height * 0.8)
        while !Task.isCancelled {
            lesson.scatter()
            await pause(0.8)
            for (box, app) in [WindowsLessonModel.apps[0], WindowsLessonModel.apps[2]].enumerated() {
                guard let window = lesson.windows.first(where: { $0.app == app }) else { continue }
                let rect = driver.frame(of: window, in: screen)
                let titleBar = CGPoint(x: rect.midX, y: rect.minY + 8)
                await glide(to: titleBar, over: 0.6)
                await pause(0.2)
                driver.begin(window, at: titleBar, in: screen)
                await glide(to: CGPoint(x: size.width / 2, y: 14), over: 0.8, dragging: true)
                // The strip, then the layouts once the hold is up.
                await pause(Double(Self.dwellMs) / 1000 + 0.7)
                guard let target = boxPoint(box) else { driver.end(in: screen); break }
                await glide(to: target, over: 0.6, dragging: true)
                await pause(0.7)
                driver.end(in: screen)
                await pause(0.9)
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
    private let m = NotchMetrics(scale: 1)
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
                    NotchShape(topCornerRadius: m.rootTopRadiusCompact, bottomCornerRadius: m.rootBottomRadiusCompact)
                        .fill(Color.black)
                        .frame(width: NotchGeometry.standardNotchSize.width, height: NotchGeometry.standardNotchSize.height)
                        .offset(x: geo.size.width / 2 - NotchGeometry.standardNotchSize.width / 2)
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
        case .access:
            SetupShellStep(title: "Allow Accessibility", subtitle: "The one permission MacsPane needs to move windows.",
                           symbol: "lock.shield")
        case .drag:
            SetupShellStep(title: "Try the drag", subtitle: "The gesture you'll use on every window, practised on samples.",
                           symbol: "rectangle.split.2x1")
        case .layouts:
            SetupShellStep(title: "Make it yours",
                           subtitle: "Pick the layouts the notch offers, how long to hold, and how MacsPane starts.",
                           symbol: "slider.horizontal.3")
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

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
        window = nil
        if !NSApp.windows.contains(where: { $0.isVisible && $0 !== notification.object as? NSWindow && $0.canBecomeKey }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
#endif
