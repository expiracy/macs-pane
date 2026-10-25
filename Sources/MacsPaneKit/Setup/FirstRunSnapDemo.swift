#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// A sample desk's notch, driven the way `WindowSnapController` drives the app's: the notch is the app's
/// own (`MacsPaneNotchView` on a host of the setup's own), a drag that reaches it widens it into the
/// strip, holding still opens the layouts with the recommended presets on the left island and your
/// presets on the right, and letting go on a target moves the sample windows there. The practice step
/// feeds it your drag; the welcome page feeds it a scripted one.
final class SetupNotchDriver: ObservableObject {
    let lesson: WindowsLessonModel
    let host: MacsPaneSnapHost
    /// The window being dragged and where the pointer is, in the stage's space.
    @Published private(set) var dragging: String?
    @Published private(set) var pointer: CGPoint?
    /// What the last release did, for the line under the practice.
    @Published var lastDrop: String?
    /// Where in the window the drag picked it up.
    private var grab = CGSize.zero

    init(config: MacsPaneConfig, dwellMs: Int? = nil) {
        lesson = WindowsLessonModel(config: config)
        host = MacsPaneSnapHost(config: WindowsLessonModel.config(from: config), recents: RecentWindowsService())
        if let dwellMs { host.dwellMs = dwellMs }
    }

    /// The notch sized for a sketched screen this wide, as the app sizes it for a real one.
    func fit(width: CGFloat) {
        host.notchSize = NotchGeometry.standardNotchSize
        host.screenWidth = width
        host.hasRealNotch = true
    }

    // MARK: - Geometry of the sample screen

    /// The sample screen below the sketched menu bar, in a stage `size`.
    static func screen(in size: CGSize) -> CGRect {
        let bar = NotchGeometry.standardNotchSize.height
        return CGRect(x: 8, y: bar + 8, width: size.width - 16, height: size.height - bar - 16)
    }

    static func place(_ unit: CGRect, in screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + unit.minX * screen.width, y: screen.minY + unit.minY * screen.height,
               width: unit.width * screen.width, height: unit.height * screen.height)
    }

    /// Where a window is drawn: its place, or under the pointer while it is dragged.
    func frame(of window: WindowsLessonModel.Window, in screen: CGRect) -> CGRect {
        let rect = Self.place(window.frame, in: screen).insetBy(dx: 2, dy: 2)
        guard dragging == window.id, let pointer else { return rect }
        return CGRect(origin: CGPoint(x: pointer.x - grab.width, y: pointer.y - grab.height), size: rect.size)
    }

    /// The notch drawn open, as mid-drag with Safari, for a picture that only shows it.
    func showPickerOpen() {
        host.dwellMs = 0
        host.windowSnap.begin(visibleFrame: WindowsLessonModel.visibleFrame,
                              suggestions: lesson.pairings(for: WindowsLessonModel.apps[0]))
        host.setWindowDragActive(true)
        host.setPointerInside(true, at: nil)
    }

    // MARK: - Dragging

    /// A drag picked up `window` by its title bar at `start`.
    func begin(_ window: WindowsLessonModel.Window, at start: CGPoint, in screen: CGRect) {
        let rect = Self.place(window.frame, in: screen)
        grab = CGSize(width: start.x - rect.minX, height: start.y - rect.minY)
        dragging = window.id
        pointer = start
        lastDrop = nil
        host.windowSnap.begin(visibleFrame: WindowsLessonModel.visibleFrame, suggestions: lesson.pairings(for: window.app))
        host.setWindowDragActive(true)
    }

    func move(to point: CGPoint) {
        pointer = point
        let middle = host.screenWidth / 2
        if host.isSnapPickerOpen {
            // Open: the picker and its islands are the target; leaving them closes it after a moment.
            let size = host.snapPickerSize
            let picker = CGRect(x: middle - size.width / 2, y: 0, width: size.width, height: size.height)
            let inside = picker.insetBy(dx: -16, dy: -16).contains(point)
            host.setPointerInside(inside, at: inside ? point : nil)
            if inside { host.windowSnap.pointerMoved(toPanelLocal: point) }
        } else {
            // On the widened notch, holding still opens the layouts.
            let size = host.windowDragTargetSize
            let onStrip = CGRect(x: middle - size.width / 2, y: 0, width: size.width, height: size.height + 12)
                .contains(point)
            host.setWindowOnTarget(onStrip)
            host.setPointerInside(onStrip, at: onStrip ? point : nil)
        }
    }

    /// Letting go: snap to the aimed target, or leave the window where it was dropped.
    func end(in screen: CGRect) {
        guard let id = dragging, let i = lesson.windows.firstIndex(where: { $0.id == id }) else { return }
        let window = lesson.windows[i]
        let dropped = frame(of: window, in: screen)
        let snap = host.windowSnap
        let aimedLayout = snap.highlightedLayoutBox?.layoutName
        let commit = snap.end()
        let wasOpen = host.isSnapPickerOpen
        host.setWindowDragActive(false)
        if wasOpen {
            host.collapseSnapPicker { [weak host] in host?.windowSnap.cancel() }
        } else {
            host.cancelPendingHoverTransitions()
            snap.cancel()
        }
        switch commit {
        case .layoutBox(let frame)?, .zone(_, let frame)?:
            withAnimation(NotchMotion.land) { lesson.place(window.app, at: WindowsLessonModel.unit(frame)) }
            lesson.progress.insert(.snapped)
            lastDrop = "Snapped into \(aimedLayout ?? "place")."
        case .pairing(let placements)?:
            withAnimation(NotchMotion.land) { lesson.apply(placements) }
            lesson.progress.insert(.snapped)
            lastDrop = "Placed \(placements.compactMap(\.window.title).joined(separator: " + ")) together."
        case .preset(let presetID)?:
            withAnimation(NotchMotion.land) { lesson.apply(presetID: presetID) }
            lesson.progress.insert(.snapped)
            lastDrop = "Opened \(lesson.config.presets.first { $0.id == presetID }?.name ?? "the preset"), each app in its box."
        case nil:
            let unit = CGRect(x: (dropped.minX - screen.minX) / screen.width, y: (dropped.minY - screen.minY) / screen.height,
                              width: dropped.width / screen.width, height: dropped.height / screen.height)
            lesson.windows[i].frame = CGRect(x: min(max(unit.minX, 0), 1 - unit.width),
                                             y: min(max(unit.minY, 0), 1 - unit.height),
                                             width: unit.width, height: unit.height)
            lastDrop = wasOpen ? "Let go outside the picker's targets, so the window stays where you put it." : nil
        }
        dragging = nil
        pointer = nil
    }
}

/// The sample screen: its windows, the ghost of where the aimed target puts them, and the app's notch,
/// in a stage space that is also the notch's panel space, so the pointer feeds it as it is. Interactive,
/// the windows are dragged by their title bars; otherwise `cursor` draws the scripted pointer.
struct SetupNotchStage: View {
    @ObservedObject var driver: SetupNotchDriver
    @ObservedObject var lesson: WindowsLessonModel
    @ObservedObject var host: MacsPaneSnapHost
    let size: CGSize
    var interactive = true
    var cursor: CGPoint?
    static let space = "setupSnapStage"

    init(driver: SetupNotchDriver, size: CGSize, interactive: Bool = true, cursor: CGPoint? = nil) {
        self.driver = driver
        self.lesson = driver.lesson
        self.host = driver.host
        self.size = size
        self.interactive = interactive
        self.cursor = cursor
    }

    var body: some View {
        let screen = SetupNotchDriver.screen(in: size)
        ZStack(alignment: .topLeading) {
            ForEach(lesson.windows) { window in
                let rect = driver.frame(of: window, in: screen)
                SetupSampleWindow(app: window.app, lifted: driver.dragging == window.id)
                    .frame(width: rect.width, height: rect.height)
                    .overlay(alignment: .top) { if interactive { titleBarHandle(window, screen: screen) } }
                    .overlay(alignment: .top) { if interactive && window.id == lesson.windows.first?.id { dragCue } }
                    .position(x: rect.midX, y: rect.midY)
                    .zIndex(driver.dragging == window.id ? 2 : 1)
            }
            SnapLessonGhosts(snap: host.windowSnap, screen: screen) { lesson.progress.insert(.aimed) }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .zIndex(3)
            MacsPaneNotchView(host: host)
                .frame(width: size.width, height: size.height, alignment: .top)
                .zIndex(4)
            if let cursor {
                Image(nsImage: NSCursor.arrow.image)
                    .position(x: cursor.x + NSCursor.arrow.image.size.width / 2 - NSCursor.arrow.hotSpot.x,
                              y: cursor.y + NSCursor.arrow.image.size.height / 2 - NSCursor.arrow.hotSpot.y)
                    .zIndex(5)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: Self.space)
        .onAppear { driver.fit(width: size.width) }
        .onChange(of: size) { _, size in driver.fit(width: size.width) }
        .onChange(of: host.stage) { _, stage in
            if stage == .picker { lesson.progress.insert(.pickerOpened) }
        }
    }

    /// Points at the handle until the picker has been opened once.
    @ViewBuilder private var dragCue: some View {
        if !lesson.progress.contains(.pickerOpened) && driver.dragging == nil {
            Label("Drag the title bar to the notch", systemImage: "arrow.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor))
                .fixedSize()
                .offset(y: -28)
                .allowsHitTesting(false)
        }
    }

    /// The title bar is the only handle, as on a real window.
    private func titleBarHandle(_ window: WindowsLessonModel.Window, screen: CGRect) -> some View {
        Color.clear
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    if driver.dragging != window.id { driver.begin(window, at: value.startLocation, in: screen) }
                    driver.move(to: value.location)
                }
                .onEnded { _ in driver.end(in: screen) })
            .help("Drag by the title bar")
    }
}

/// The practice step: drag a sample window by its title bar to the notch, with the hold time beside it
/// to feel the difference.
struct FirstRunSnapDemo: View {
    @StateObject private var driver: SetupNotchDriver
    /// Offscreen-render seed only: open the notch mid-drag and aim at the first preset.
    private let previewPicker: Bool
    /// Which of `MacsPaneConfig.dwellChoices` the hold is, the menu's Hold for.
    @Binding var dwellIndex: Int

    init(config: MacsPaneConfig, previewPicker: Bool = false, dwellIndex: Binding<Int>) {
        self.previewPicker = previewPicker
        _dwellIndex = dwellIndex
        _driver = StateObject(wrappedValue: SetupNotchDriver(config: config))
    }

    var body: some View {
        FirstRunSnapPractice(driver: driver, lesson: driver.lesson, host: driver.host, dwellIndex: $dwellIndex)
            .onAppear { if previewPicker { preview() } }
            .onChange(of: dwellIndex) { _, index in
                driver.host.dwellMs = MacsPaneConfig.dwellChoices[index]
            }
    }

    /// The notch open as mid-drag with Safari, its first preset aimed at, for a still render.
    private func preview() {
        let host = driver.host
        driver.showPickerOpen()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let tile = host.windowSnap.presetFrames[0] {
                host.windowSnap.pointerMoved(toPanelLocal: CGPoint(x: tile.midX, y: tile.midY))
            }
        }
    }
}

private struct FirstRunSnapPractice: View {
    @ObservedObject var driver: SetupNotchDriver
    @ObservedObject var lesson: WindowsLessonModel
    @ObservedObject var host: MacsPaneSnapHost
    @Binding var dwellIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SetupIntroRow(text: "Drag a sample window to the notch.") {
                // The same choice as the menu's Hold for, here where you feel it.
                Text("Hold for").foregroundStyle(.secondary)
                Picker("Hold for", selection: $dwellIndex) {
                    ForEach(MacsPaneConfig.dwellChoices.indices, id: \.self) { index in
                        Text(MacsPaneMenu.seconds(MacsPaneConfig.dwellChoices[index])).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("How long a window rests on the notch before your layouts open")
                Button("Put the windows back") { withAnimation(NotchMotion.settle) { lesson.scatter() } }
                    .disabled(lesson.windows == WindowsLessonModel.scattered)
            }
            SetupDesktop(height: SetupStage.height, showsMenuItems: host.stage == .rest) {
                GeometryReader { geo in SetupNotchStage(driver: driver, size: geo.size) }
            }
            HStack(alignment: .top, spacing: 18) {
                SetupLessonStep(title: "Drag a window up and hold it on the notch",
                                detail: "The notch widens to show where. Hold still there and the layouts open.",
                                done: lesson.progress.contains(.pickerOpened))
                SetupLessonStep(title: "Aim at a box or a preset",
                                detail: "Recommended presets are on the left, yours on the right. A ghost shows where each window will land.",
                                done: lesson.progress.contains(.aimed))
                SetupLessonStep(title: "Let go to snap it",
                                detail: "Letting go anywhere else leaves it where you put it.",
                                done: lesson.progress.contains(.snapped))
            }
            SnapLessonStatus(snap: host.windowSnap, strip: host.dragStrip, stage: host.stage,
                             dragging: driver.dragging != nil, lastDrop: driver.lastDrop, layouts: lesson.offeredLayoutNames)
        }
    }
}

/// Where the aimed target would put the windows, drawn on the sample screen.
private struct SnapLessonGhosts: View {
    @ObservedObject var snap: WindowSnapViewModel
    let screen: CGRect
    let onAim: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(units.enumerated()), id: \.offset) { _, unit in
                let ghost = SetupNotchDriver.place(unit, in: screen).insetBy(dx: 2, dy: 2)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NotchPalette.dropGhostFill)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(NotchPalette.strokeAccent, lineWidth: 2))
                    .frame(width: ghost.width, height: ghost.height)
                    .position(x: ghost.midX, y: ghost.midY)
            }
        }
        .allowsHitTesting(false)
        .animation(NotchMotion.fast, value: units)
        .onChange(of: units.isEmpty) { _, empty in if !empty { onAim() } }
    }

    /// The aimed target's boxes as top-left unit rects of the screen.
    private var units: [CGRect] {
        if let box = snap.highlightedLayoutBox { return [WindowsLessonModel.topLeft(box.region)] }
        if let i = snap.highlightedSuggestion, snap.suggestions.indices.contains(i) {
            return snap.suggestions[i].pairing.placements.map { WindowsLessonModel.unit($0.frame) }
        }
        if let i = snap.highlightedPreset, snap.presets.indices.contains(i) { return snap.presets[i].boxes.map(\.rect) }
        return []
    }
}

/// One line under the practice: what the drag is doing now, or what letting go will do.
private struct SnapLessonStatus: View {
    @ObservedObject var snap: WindowSnapViewModel
    @ObservedObject var strip: NotchDragStripModel
    let stage: MacsPaneSnapHost.Stage
    let dragging: Bool
    let lastDrop: String?
    let layouts: [String]

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var text: String {
        if let box = snap.highlightedLayoutBox { return "Let go to snap it into \(box.layoutName), box \(box.boxIndex + 1)." }
        if let i = snap.highlightedSuggestion, snap.suggestions.indices.contains(i) {
            return "Let go to place \(snap.suggestions[i].label) together."
        }
        if let i = snap.highlightedPreset, snap.presets.indices.contains(i) {
            let preset = snap.presets[i]
            return "Let go to open \(preset.name)" + (preset.apps.map { ": \($0)." } ?? ".")
        }
        if stage == .picker { return "Aim at a box in a layout, a recommended preset on the left, or one of yours on the right." }
        if dragging {
            return strip.windowOnTarget ? "Hold it still here and the layouts open."
                                        : "The notch has widened. Bring the window onto it and hold still."
        }
        if let lastDrop { return lastDrop }
        return "The notch offers the layouts you choose in the menu: "
            + "\(ListFormatter.localizedString(byJoining: layouts))."
    }
}
#endif
