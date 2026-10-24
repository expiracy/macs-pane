#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// MacsPane's first-time setup: the setup shell with four steps: what it does, Accessibility, the drag
/// on sample windows, and which layouts the picker offers. Shown on a first run and from the dropdown's Setup button.
final class MacsPaneSetupModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, access, drag, layouts }

    @Published var step: Step = .welcome
    @Published private(set) var authorized: Bool
    let app: MacsPaneModel
    var onFinish: (() -> Void)?
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
            }
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            SetupWelcomeHero()
            HStack(alignment: .top, spacing: 12) {
                feature("rectangle.split.2x1", "Drag to the notch",
                        "Hold a window on the notch and your layouts open. Let go on a box and the window fills it.")
                feature("square.stack.3d.up", "Save presets",
                        "Arrange your windows once, save them as a preset, and put them all back with one click.")
                feature("menubar.rectangle", "Lives in the menu bar",
                        "Presets, layouts, what the notch offers and Undo all sit under the MacsPane icon.")
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
        FirstRunSnapDemo(lesson: WindowsLessonModel(holdDelay: Double(app.config.dwellMs) / 1000))
    }

    private var layouts: some View {
        let offered = app.config.windows.dragBarLayoutIDs
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Click a layout to add it to the picker or take it out.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(offered.count == 1 ? "1 in the picker" : "\(offered.count) in the picker")
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
        }
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
        .help(on ? "In the picker · click to take it out" : "Not in the picker · click to add it")
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

/// The welcome step's picture: a desktop whose two windows sit snapped side by side under the notch.
private struct SetupWelcomeHero: View {
    private let m = NotchMetrics(scale: 1)

    var body: some View {
        SetupDesktop(height: 250) {
            GeometryReader { geo in
                let bar = NotchGeometry.standardNotchSize.height
                let half = (geo.size.width - 30) / 2
                let height = geo.size.height - bar - 22
                ZStack(alignment: .topLeading) {
                    SetupSampleWindow(app: WindowsLessonModel.apps[0])
                        .frame(width: half, height: height)
                        .offset(x: 12, y: bar + 10)
                    SetupSampleWindow(app: WindowsLessonModel.apps[2])
                        .frame(width: half, height: height)
                        .offset(x: 18 + half, y: bar + 10)
                    NotchShape(topCornerRadius: m.rootTopRadiusCompact, bottomCornerRadius: m.rootBottomRadiusCompact)
                        .fill(Color.black)
                        .frame(width: NotchGeometry.standardNotchSize.width, height: bar)
                        .offset(x: geo.size.width / 2 - NotchGeometry.standardNotchSize.width / 2)
                }
            }
        }
        .accessibilityHidden(true)
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
            SetupShellStep(title: "Choose your layouts",
                           subtitle: "The shapes the notch offers while you drag. Change them any time from the menu bar.",
                           symbol: "square.grid.2x2")
        }
    }
}

/// Opens the setup window and puts the app back to menu-bar-only when it closes. Closing it counts as
/// done; the dropdown's Setup button brings it back.
final class MacsPaneSetupController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(app: MacsPaneModel) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let model = MacsPaneSetupModel(app: app)
        model.onFinish = { [weak self] in self?.window?.close() }
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
