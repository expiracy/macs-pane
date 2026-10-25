#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// Drag a sample window by its title bar toward the top of the sketched screen. The notch is the app's
/// own (`MacsPaneNotchView` on a host of the setup's own): it widens into the drag strip, holding still
/// on it for the user's hold time opens the layouts with the recommended presets on the left island and
/// your presets on the right, the target under the pointer lights with a ghost of where the window(s)
/// will land, and letting go moves the sample windows there.
struct FirstRunSnapDemo: View {
    @StateObject private var lesson: WindowsLessonModel
    @StateObject private var host: MacsPaneSnapHost
    @State private var dragging: String?
    @State private var grab = CGSize.zero
    @State private var pointer: CGPoint?
    @State private var lastDrop: String?
    private static let space = "setupSnapStage"
    private static let stageHeight = SetupStage.height
    /// Offscreen-render seed only: open the notch mid-drag and aim at the first preset.
    private let previewPicker: Bool

    init(config: MacsPaneConfig, previewPicker: Bool = false) {
        self.previewPicker = previewPicker
        _lesson = StateObject(wrappedValue: WindowsLessonModel(config: config))
        _host = StateObject(wrappedValue: MacsPaneSnapHost(config: WindowsLessonModel.config(from: config),
                                                           recents: RecentWindowsService()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SetupIntroRow(text: "Drag a sample window to the notch, as you will with real ones. Nothing on your Mac moves.") {
                Button("Put the windows back") { withAnimation(NotchMotion.settle) { lesson.scatter() } }
                    .disabled(lesson.windows == WindowsLessonModel.scattered)
            }
            SetupDesktop(height: Self.stageHeight, showsMenuItems: host.stage == .rest) {
                GeometryReader { geo in stage(size: geo.size) }
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
                             dragging: dragging != nil, lastDrop: lastDrop, layouts: lesson.offeredLayoutNames)
        }
        .onChange(of: host.stage) { _, stage in
            if stage == .picker { lesson.progress.insert(.pickerOpened) }
        }
        .onAppear { if previewPicker { preview() } }
    }

    /// The notch open as mid-drag with Safari, its first preset aimed at, for a still render.
    private func preview() {
        host.dwellMs = 0
        host.windowSnap.begin(visibleFrame: WindowsLessonModel.visibleFrame,
                              suggestions: lesson.pairings(for: WindowsLessonModel.apps[0]))
        host.setWindowDragActive(true)
        host.setPointerInside(true, at: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let tile = host.windowSnap.presetFrames[0] {
                host.windowSnap.pointerMoved(toPanelLocal: CGPoint(x: tile.midX, y: tile.midY))
            }
        }
    }

    // MARK: - Stage

    private func screen(_ size: CGSize) -> CGRect {
        let bar = NotchGeometry.standardNotchSize.height
        return CGRect(x: 8, y: bar + 8, width: size.width - 16, height: size.height - bar - 16)
    }

    private func place(_ unit: CGRect, in screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + unit.minX * screen.width, y: screen.minY + unit.minY * screen.height,
               width: unit.width * screen.width, height: unit.height * screen.height)
    }

    private func stage(size: CGSize) -> some View {
        let screen = screen(size)
        return ZStack(alignment: .topLeading) {
            ForEach(lesson.windows) { window in
                let rect = frame(of: window, in: screen)
                SetupSampleWindow(app: window.app, lifted: dragging == window.id)
                    .frame(width: rect.width, height: rect.height)
                    .overlay(alignment: .top) { titleBarHandle(window, screen: screen) }
                    .overlay(alignment: .top) { if window.id == lesson.windows.first?.id { dragCue } }
                    .position(x: rect.midX, y: rect.midY)
                    .zIndex(dragging == window.id ? 2 : 1)
            }
            SnapLessonGhosts(snap: host.windowSnap, screen: screen) { lesson.progress.insert(.aimed) }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .zIndex(3)
            // The app's notch, in a panel space that is this stage's: the pointer feeds it as it is.
            MacsPaneNotchView(host: host)
                .frame(width: size.width, height: size.height, alignment: .top)
                .zIndex(4)
        }
        .coordinateSpace(name: Self.space)
        .onAppear { fit(size) }
        .onChange(of: size) { _, size in fit(size) }
    }

    /// The practice notch sized for this sketched screen, as the app sizes it for a real one.
    private func fit(_ size: CGSize) {
        host.notchSize = NotchGeometry.standardNotchSize
        host.screenWidth = size.width
        host.hasRealNotch = true
    }

    private func frame(of window: WindowsLessonModel.Window, in screen: CGRect) -> CGRect {
        let rect = place(window.frame, in: screen).insetBy(dx: 2, dy: 2)
        guard dragging == window.id, let pointer else { return rect }
        return CGRect(origin: CGPoint(x: pointer.x - grab.width, y: pointer.y - grab.height), size: rect.size)
    }

    /// Points at the handle until the picker has been opened once.
    @ViewBuilder private var dragCue: some View {
        if !lesson.progress.contains(.pickerOpened) && dragging == nil {
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
                .onChanged { value in dragChanged(window, value: value, screen: screen) }
                .onEnded { _ in dragEnded(window, screen: screen) })
            .help("Drag by the title bar")
    }

    // MARK: - Dragging, as `WindowSnapController` drives the app's notch

    private func dragChanged(_ window: WindowsLessonModel.Window, value: DragGesture.Value, screen: CGRect) {
        if dragging != window.id {
            let rect = place(window.frame, in: screen)
            grab = CGSize(width: value.startLocation.x - rect.minX, height: value.startLocation.y - rect.minY)
            dragging = window.id
            lastDrop = nil
            host.windowSnap.begin(visibleFrame: WindowsLessonModel.visibleFrame,
                                  suggestions: lesson.pairings(for: window.app))
            host.setWindowDragActive(true)
        }
        let point = value.location
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

    private func dragEnded(_ window: WindowsLessonModel.Window, screen: CGRect) {
        guard let i = lesson.windows.firstIndex(where: { $0.id == window.id }) else { return }
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
        case .preset(let id)?:
            withAnimation(NotchMotion.land) { lesson.apply(presetID: id) }
            lesson.progress.insert(.snapped)
            lastDrop = "Opened \(lesson.config.presets.first { $0.id == id }?.name ?? "the preset"), each app in its box."
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

/// Where the aimed target would put the windows, drawn on the sample screen.
private struct SnapLessonGhosts: View {
    @ObservedObject var snap: WindowSnapViewModel
    let screen: CGRect
    let onAim: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(units.enumerated()), id: \.offset) { _, unit in
                let ghost = CGRect(x: screen.minX + unit.minX * screen.width, y: screen.minY + unit.minY * screen.height,
                                   width: unit.width * screen.width, height: unit.height * screen.height)
                    .insetBy(dx: 2, dy: 2)
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
