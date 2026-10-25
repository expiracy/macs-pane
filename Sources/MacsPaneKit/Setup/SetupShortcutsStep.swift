#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// The shortcuts step: setup's suggested keys, each with its switch, tried on a sample desk. While the
/// step is showing, your shortcuts don't run in other apps: the keys come here, move the sample window
/// you clicked, and record new keys for a suggestion.
final class SetupShortcutsModel: ObservableObject {
    let app: MacsPaneModel
    let lesson: WindowsLessonModel
    /// The sample window the keys move, as clicking a window makes it the one you're in.
    @Published var focused = WindowsLessonModel.apps[0].name
    /// The suggestion waiting for new keys, and a word on keys that can't be one.
    @Published private(set) var recording: ShortcutSuggestion?
    @Published private(set) var hint: String?
    /// What the last keys did, for the line under the step.
    @Published private(set) var lastPress: String?
    /// The keys just pressed, drawn over the desk for a moment.
    @Published private(set) var pressed: KeyShortcut?
    private var pressCount = 0
    private var monitor: Any?

    init(app: MacsPaneModel) {
        self.app = app
        lesson = WindowsLessonModel(config: app.config)
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// The step came into view (the keys come here) or left it (they go back to every app).
    func setActive(_ active: Bool) {
        guard active != (monitor != nil) else { return }
        if active {
            app.setShortcutsSuspended(true)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        } else {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            recording = nil
            hint = nil
            app.setShortcutsSuspended(false)
        }
    }

    /// A suggestion's keys clicked: wait for new ones, or stop waiting.
    func record(_ suggestion: ShortcutSuggestion) {
        recording = recording == suggestion ? nil : suggestion
        hint = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let keys = KeyShortcut(event: event)
        if let target = recording {
            switch (keys.keyCode, keys.modifiers.isEmpty) {
            case (53, true):
                break
            case (51, true), (117, true):
                app.removeShortcut(for: target.action)
            default:
                guard keys.isUsable else { hint = "Hold ⌘, ⌃ or ⌥ too"; return nil }
                app.setShortcut(keys, for: target.action)
            }
            recording = nil
            hint = nil
            return nil
        }
        let config = app.config
        guard let assigned = config.activeShortcuts.first(where: { $0.shortcut == keys }) else {
            if let off = config.shortcutSuggestions.first(where: { config.keys(for: $0) == keys }) {
                lastPress = "\(off.name) is switched off. Switch it on to try it."
                return nil
            }
            return event
        }
        show(keys)
        switch assigned.action {
        case let .layoutBox(layoutID, box):
            guard let layout = config.windows.layoutCatalog.first(where: { $0.id == layoutID }),
                  layout.boxes.indices.contains(box),
                  let window = lesson.windows.first(where: { $0.id == focused }) else { return nil }
            withAnimation(NotchMotion.land) { lesson.place(window.app, at: WindowsLessonModel.topLeft(layout.boxes[box])) }
            let name = config.shortcutSuggestions.first { $0.action == assigned.action }?.name
                ?? app.shortcutOwner(keys)?.name ?? layout.name
            lastPress = "\(keys.displayName) sent \(window.app.name) to \(name)."
        case .preset:
            lastPress = "\(keys.displayName) applies \(app.shortcutOwner(keys)?.name ?? "a preset"). "
                + "Try it in any app once setup is done."
        }
        return nil
    }

    private func show(_ keys: KeyShortcut) {
        pressCount += 1
        let count = pressCount
        withAnimation(.bouncy(duration: 0.25)) { pressed = keys }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self, self.pressCount == count else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.pressed = nil }
        }
    }
}

struct SetupShortcutsStep: View {
    @ObservedObject var model: SetupShortcutsModel
    @ObservedObject var app: MacsPaneModel
    @ObservedObject var lesson: WindowsLessonModel

    init(model: SetupShortcutsModel) {
        self.model = model
        self.app = model.app
        self.lesson = model.lesson
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SetupIntroRow(text: "Click a sample window, then press keys you've switched on. Nothing on your Mac moves.") {
                Button("Put the windows back") { withAnimation(NotchMotion.settle) { lesson.scatter() } }
                    .disabled(lesson.windows == WindowsLessonModel.scattered)
            }
            SetupDesktop(height: SetupStage.height) {
                ZStack(alignment: .top) {
                    SetupRestingNotch()
                    GeometryReader { geo in desk(in: geo.size) }
                }
            }
            .overlay(alignment: .bottom) {
                if let pressed = model.pressed {
                    SetupKeyCaps(shortcut: pressed)
                        .padding(.bottom, 18)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 8) {
                ForEach(app.config.shortcutSuggestions) { suggestionRow($0) }
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - The desk

    /// The sample windows; the one you clicked is in front with a ring, and the keys move it.
    private func desk(in size: CGSize) -> some View {
        let screen = SetupNotchDriver.screen(in: size)
        return ZStack(alignment: .topLeading) {
            ForEach(lesson.windows) { window in
                let rect = SetupNotchDriver.place(window.frame, in: screen).insetBy(dx: 2, dy: 2)
                let focused = model.focused == window.id
                SetupSampleWindow(app: window.app, lifted: focused)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: focused ? 2 : 0)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .zIndex(focused ? 2 : 1)
                    .onTapGesture { model.focused = window.id }
                    .help(focused ? "The keys move this window" : "Click to make this the window you're in")
                    .accessibilityAddTraits(focused ? [.isSelected] : [])
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: - Suggestions

    private func suggestionRow(_ suggestion: ShortcutSuggestion) -> some View {
        let config = app.config
        let on = config.isOn(suggestion)
        return SetupCard(padding: 8) {
            HStack(spacing: 10) {
                if let (boxes, box) = boxes(of: suggestion) {
                    MacsPaneLayoutGlyph(boxes: boxes, size: CGSize(width: 34, height: 22), highlighted: box)
                        .opacity(on ? 1 : 0.6)
                }
                Text(suggestion.name).font(.callout.weight(.semibold))
                Spacer(minLength: 4)
                keysChip(suggestion, keys: config.keys(for: suggestion), on: on)
                Toggle(suggestion.name, isOn: Binding(get: { on }, set: { app.setSuggestion(suggestion, on: $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    /// The keys, clicked to press others: a dashed prompt while it waits.
    private func keysChip(_ suggestion: ShortcutSuggestion, keys: KeyShortcut, on: Bool) -> some View {
        let recording = model.recording == suggestion
        return Button { model.record(suggestion) } label: {
            Text(recording ? (model.hint ?? "Type keys") : keys.displayName)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(recording ? AnyShapeStyle(Color.accentColor) : on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(recording ? 0.03 : 0.07)))
                .overlay {
                    if recording {
                        Capsule().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help(suggestion, keys: keys, recording: recording))
        .accessibilityLabel("\(suggestion.name) keys, \(keys.displayName)")
    }

    private func help(_ suggestion: ShortcutSuggestion, keys: KeyShortcut, recording: Bool) -> String {
        if recording { return "Press the keys for \(suggestion.name); esc keeps these, ⌫ goes back to the suggested ones" }
        if let owner = app.shortcutOwner(keys), owner.action != suggestion.action {
            return "Switching this on takes \(keys.displayName) from \(owner.name)"
        }
        return "Click to choose other keys"
    }

    /// The layout's boxes and which one the suggestion sends a window to.
    private func boxes(of suggestion: ShortcutSuggestion) -> ([SnapRegion], Int)? {
        guard case let .layoutBox(layoutID, box) = suggestion.action,
              let layout = app.config.windows.layoutCatalog.first(where: { $0.id == layoutID }) else { return nil }
        return (layout.boxes, box)
    }

    private var status: String {
        if let recording = model.recording {
            return "Press the keys for \(recording.name). esc keeps the ones it has."
        }
        if let lastPress = model.lastPress { return lastPress }
        let config = app.config
        guard let first = config.shortcutSuggestions.first(where: config.isOn) else {
            return "Switch on the ones you'd like. They work in every app, on the window you're in, "
                + "and the menu's Shortcuts list has them all."
        }
        let window = lesson.windows.first { $0.id == model.focused }?.app.name ?? "a window"
        return "Press \(config.keys(for: first).displayName) to send \(window) to the \(first.name.lowercased())."
    }
}
#endif
