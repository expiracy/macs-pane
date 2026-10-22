#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// MacsPane's first-time setup: the setup shell with four steps — what it does, Accessibility, the drag
/// on sample windows, and which layouts the picker offers. Shown on a first run and from Settings › Run setup again.
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
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    explainer("rectangle.split.2x1", "Drag a window to the notch",
                              "Hold it there and your layouts open. Let go on a box and the window fills it.")
                    explainer("square.grid.2x2", "Apply a preset from the menu bar",
                              "Arrange your windows once, save them as a preset, and put them back with one click.")
                    explainer("menubar.rectangle", "Everything else is in the menu bar",
                              "Undo, saving layouts and presets, and Settings live under the MacsPane icon.")
                }
                .padding(10)
            }
            Spacer(minLength: 0)
        }
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                HStack(spacing: 13) {
                    Image(systemName: "hand.point.up.left").font(.title3).foregroundStyle(Color.accentColor)
                        .frame(width: 27)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Accessibility").font(.subheadline.weight(.semibold))
                        Text("Lets MacsPane move and resize other apps' windows. It reads nothing else.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 14)
                    if model.authorized {
                        Label("Granted", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Grant Access") { model.grant() }
                    }
                }
                .padding(.vertical, 12).padding(.horizontal, 8)
            }
            Label(model.authorized
                    ? "All set. Dragging a window to the notch now opens your layouts."
                    : "macOS opens System Settings at the Accessibility list. This step notices as soon as it's on. "
                      + "Until then, dragging a window to the notch does nothing.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var drag: some View {
        VStack(alignment: .leading, spacing: 16) {
            FirstRunSnapDemo(lesson: WindowsLessonModel(holdDelay: Double(app.config.dwellMs) / 1000))
            VStack(alignment: .leading, spacing: 10) {
                explainer("square.stack.3d.up", "Presets",
                          "Arrange your windows, then choose “Save windows as a preset” in the menu bar. "
                          + "Clicking the preset there puts them all back.")
            }
            Spacer(minLength: 0)
        }
    }

    private var layouts: some View {
        let offered = app.config.windows.dragBarLayoutIDs
        return VStack(alignment: .leading, spacing: 16) {
            Text(offered.count == 1 ? "1 layout in the picker" : "\(offered.count) layouts in the picker")
                .font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(app.config.windows.layoutCatalog) { layout in
                    layoutCard(layout, on: offered.contains(layout.id))
                }
            }
            Toggle("Open MacsPane at login", isOn: Binding(
                get: { LoginItem.isEnabled }, set: { LoginItem.setEnabled($0); app.objectWillChange.send() }))
            Spacer(minLength: 0)
        }
    }

    /// A layout as a card you tick: its shape, its name, and whether the picker offers it.
    private func layoutCard(_ layout: WindowLayout, on: Bool) -> some View {
        Button { app.toggleBar(layout.id) } label: {
            VStack(spacing: 10) {
                MacsPaneLayoutGlyph(boxes: layout.boxes, size: CGSize(width: 96, height: 60))
                HStack(spacing: 6) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? Color.accentColor : .secondary)
                    Text(layout.name).lineLimit(1)
                }
                .font(.callout)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(on ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? "In the picker · click to take it out" : "Not in the picker · click to add it")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func explainer(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension MacsPaneSetupModel.Step {
    var shellStep: SetupShellStep {
        switch self {
        case .welcome:
            SetupShellStep(title: "Welcome to MacsPane", subtitle: "Snap any window into place by dragging it to the notch.",
                           symbol: "hand.wave")
        case .access:
            SetupShellStep(title: "Allow Accessibility", subtitle: "The one permission MacsPane needs to move windows.",
                           symbol: "lock.shield")
        case .drag:
            SetupShellStep(title: "Try the drag", subtitle: "The gesture you'll use on every window, practised on samples.",
                           symbol: "rectangle.split.2x1")
        case .layouts:
            SetupShellStep(title: "Choose your layouts",
                           subtitle: "The shapes the notch offers while you drag. Change them any time in Settings.",
                           symbol: "square.grid.2x2")
        }
    }
}

/// Opens the setup window and puts the app back to menu-bar-only when it closes. Closing it counts as
/// done — Settings › Run setup again brings it back.
final class MacsPaneSetupController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(app: MacsPaneModel) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let model = MacsPaneSetupModel(app: app)
        model.onFinish = { [weak self] in self?.window?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: MacsPaneSetupView(model: model)))
        window.title = "Set up MacsPane"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 1160, height: 720))
        window.minSize = NSSize(width: 1120, height: 680)
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
