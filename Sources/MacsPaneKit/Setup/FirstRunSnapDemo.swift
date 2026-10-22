#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// Drag a sample window by its title bar toward the top of the sketched screen. As in the app, the notch
/// first widens into the shipped drag strip (`NotchDragTargetStrip`: "Windows" · "Hold for layouts"),
/// which lights while the window is on it; holding still there for the user's own dwell opens the
/// Windows picker as `WindowSnapView` lays it out — the drag-to-top bar's layouts centred on the
/// notch, the recent-pair wing hanging off its left — the target under the pointer lights up with a
/// ghost of where the window(s) will land, and letting go snaps there.
struct FirstRunSnapDemo: View {
    @ObservedObject var lesson: WindowsLessonModel
    @State private var dragging: String?
    @State private var grab = CGSize.zero
    @State private var pointer: CGPoint?
    @State private var pickerOpen = false
    @State private var target: Target?
    @State private var lastDrop: String?
    /// The shipped strip's own hover state: lit while the dragged window is on it.
    @StateObject private var strip = NotchDragStripModel()
    @State private var holdWork: DispatchWorkItem?
    /// Offscreen-render seed: draw the strip as mid-drag.
    @State private var previewStrip = false
    private let m = NotchMetrics(scale: 1)
    private static let space = "setupSnapStage"
    private static let stageHeight = SetupStage.height

    enum Target: Equatable {
        case box(layout: Int, box: Int)
        case pair(Int)
        case preset(Int)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SetupIntroRow(text: "Drag a sample window to the notch, as you will with real ones. Nothing on your Mac moves.") {
                Button("Put the windows back") { withAnimation(NotchMotion.settle) { lesson.scatter() } }
                    .disabled(lesson.windows == WindowsLessonModel.scattered)
            }
            SetupDesktop(height: Self.stageHeight, showsMenuItems: !pickerOpen) {
                GeometryReader { geo in stage(size: geo.size) }
            }
            HStack(alignment: .top, spacing: 18) {
                SetupLessonStep(title: "Drag a window up and hold it on the notch",
                                detail: "The notch widens to show where. Hold still there and the layouts open.",
                                done: lesson.progress.contains(.pickerOpened))
                SetupLessonStep(title: "Aim at a box, pair or preset",
                                detail: "A ghost shows where each window will land.",
                                done: lesson.progress.contains(.aimed))
                SetupLessonStep(title: "Let go to snap it",
                                detail: "Letting go anywhere else leaves it where you put it.",
                                done: lesson.progress.contains(.snapped))
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            // An offscreen render's seed: the strip lit, or the picker open with a box aimed at, as mid-drag.
            if lesson.previewStrip {
                previewStrip = true
                strip.windowOnTarget = true
            }
            guard lesson.previewAim || lesson.previewAimPair else { return }
            pickerOpen = true
            target = lesson.previewAimPair ? .pair(1) : .box(layout: 0, box: 1)
        }
    }

    private var draggedApp: WindowsLessonModel.App {
        lesson.windows.first { $0.id == dragging }?.app ?? WindowsLessonModel.apps[0]
    }

    private var pairings: [WindowsLessonModel.Pairing] { lesson.pairings(for: draggedApp) }

    /// The widened notch is up for the whole drag, until the picker takes its place.
    private var stripShown: Bool { (dragging != nil || previewStrip) && !pickerOpen }
    /// The strip at the shipped size on a 14" MacBook Pro (a third of a 1512 pt screen), as the notch is 1:1.
    private var stripWidth: CGFloat {
        NotchGeometry.dragTargetWidth(screenWidth: 1512, notchWidth: NotchGeometry.standardNotchSize.width,
                                      fraction: WindowSnapMetrics.dragWidthFraction)
    }

    private var status: String {
        switch target {
        case .box(let l, let b)?: return "Let go to snap it into \(lesson.barLayouts[l].name), box \(b + 1)."
        case .pair(let p)?: return "Let go to place \(pairings[p].label(dragged: draggedApp)) together."
        case .preset(let k)?: return "Let go to open \(lesson.presets[k].name): \(lesson.presets[k].detail)."
        case nil: break
        }
        if pickerOpen { return "Aim at a box in a layout, at a pair on the left, or at a preset on the right." }
        if stripShown {
            return strip.windowOnTarget ? "Hold it still here and the layouts open."
                                        : "The notch has widened. Bring the window onto it and hold still."
        }
        if let lastDrop { return lastDrop }
        return "The picker offers the layouts in your drag-to-top bar: "
            + "\(ListFormatter.localizedString(byJoining: lesson.barLayouts.map(\.name)))."
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
        let geometry = SetupSnapPicker(stageWidth: size.width, layouts: lesson.barLayouts.count, pairs: pairings.count,
                                       presets: lesson.presets.count)
        return ZStack(alignment: .topLeading) {
            ForEach(lesson.windows) { window in
                let rect = frame(of: window, in: screen)
                SetupSampleWindow(app: window.app, lifted: dragging == window.id)
                    .frame(width: rect.width, height: rect.height)
                    .overlay(alignment: .top) { titleBarHandle(window, screen: screen, picker: geometry) }
                    .overlay(alignment: .top) { if window.id == lesson.windows.first?.id { dragCue } }
                    .position(x: rect.midX, y: rect.midY)
                    .zIndex(dragging == window.id ? 2 : 1)
            }
            ForEach(Array(ghosts.enumerated()), id: \.offset) { _, unit in
                let ghost = place(unit, in: screen).insetBy(dx: 2, dy: 2)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NotchPalette.dropGhostFill)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(NotchPalette.strokeAccent, lineWidth: 2))
                    .frame(width: ghost.width, height: ghost.height)
                    .position(x: ghost.midX, y: ghost.midY)
                    .allowsHitTesting(false)
            }
            .zIndex(3)
            picker(geometry).zIndex(4)
        }
        .coordinateSpace(name: Self.space)
    }

    /// Where the aimed target would put things, as top-left unit rects of the screen.
    private var ghosts: [CGRect] {
        switch target {
        case .box(let l, let b)?: return [WindowsLessonModel.topLeft(lesson.barLayouts[l].boxes[b])]
        case .pair(let p)?: return pairings[p].frames
        case .preset(let k)?: return lesson.presets[k].layout.boxes.map(WindowsLessonModel.topLeft)
        case nil: return []
        }
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
    private func titleBarHandle(_ window: WindowsLessonModel.Window, screen: CGRect, picker: SetupSnapPicker) -> some View {
        Color.clear
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                .onChanged { value in dragChanged(window, value: value, screen: screen, picker: picker) }
                .onEnded { _ in dragEnded(window, screen: screen) })
            .help("Drag by the title bar")
    }

    // MARK: - Dragging

    private func dragChanged(_ window: WindowsLessonModel.Window, value: DragGesture.Value, screen: CGRect,
                             picker: SetupSnapPicker) {
        if dragging != window.id {
            let rect = place(window.frame, in: screen)
            grab = CGSize(width: value.startLocation.x - rect.minX, height: value.startLocation.y - rect.minY)
            dragging = window.id
            lastDrop = nil
        }
        pointer = value.location
        let open = pickerOpen && picker.frame.insetBy(dx: -16, dy: -16).contains(value.location)
        if pickerOpen && !open { withAnimation(NotchMotion.close) { pickerOpen = false } }
        if !open {
            // On the strip, a pause opens the layouts; every move restarts the wait, as in the app.
            let onStrip = value.location.y < NotchGeometry.standardNotchSize.height + 12
                && abs(value.location.x - picker.stageWidth / 2) < stripWidth / 2
            strip.setWindowOnTarget(onStrip)
            holdWork?.cancel(); holdWork = nil
            if onStrip {
                let work = DispatchWorkItem {
                    guard dragging != nil, strip.windowOnTarget else { return }
                    strip.reset()
                    withAnimation(NotchMotion.open) { pickerOpen = true }
                    lesson.progress.insert(.pickerOpened)
                }
                holdWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + lesson.holdDelay, execute: work)
            }
        }
        let aimed = open ? aim(at: value.location, picker: picker) : nil
        if aimed != target {
            withAnimation(NotchMotion.fast) { target = aimed }
            if aimed != nil { lesson.progress.insert(.aimed) }
        }
    }

    private func aim(at point: CGPoint, picker: SetupSnapPicker) -> Target? {
        if let p = pairings.indices.first(where: { picker.pairTile($0).contains(point) }) { return .pair(p) }
        if let k = lesson.presets.indices.first(where: { picker.presetTile($0).contains(point) }) { return .preset(k) }
        for (i, layout) in lesson.barLayouts.enumerated() {
            let inner = picker.inner(picker.familyTile(i))
            guard inner.contains(point) else { continue }
            if let b = layout.boxes.indices.first(where: {
                place(WindowsLessonModel.topLeft(layout.boxes[$0]), in: inner).contains(point)
            }) { return .box(layout: i, box: b) }
        }
        return nil
    }

    private func dragEnded(_ window: WindowsLessonModel.Window, screen: CGRect) {
        guard let i = lesson.windows.firstIndex(where: { $0.id == window.id }) else { return }
        let dropped = frame(of: window, in: screen)
        switch target {
        case .box(let l, let b)?:
            let layout = lesson.barLayouts[l]
            withAnimation(NotchMotion.land) { lesson.windows[i].frame = WindowsLessonModel.topLeft(layout.boxes[b]) }
            lesson.progress.insert(.snapped)
            lastDrop = "Snapped into \(layout.name), box \(b + 1)."
        case .pair(let p)?:
            let pairing = pairings[p]
            withAnimation(NotchMotion.land) { lesson.apply(pairing, dragged: window.app) }
            lesson.progress.insert(.snapped)
            lastDrop = "Placed \(pairing.label(dragged: window.app)) together."
        case .preset(let k)?:
            let preset = lesson.presets[k]
            withAnimation(NotchMotion.land) { lesson.apply(preset) }
            lesson.progress.insert(.snapped)
            lastDrop = "Opened \(preset.name): \(preset.detail), each in its box."
        case nil:
            let unit = CGRect(x: (dropped.minX - screen.minX) / screen.width, y: (dropped.minY - screen.minY) / screen.height,
                              width: dropped.width / screen.width, height: dropped.height / screen.height)
            lesson.windows[i].frame = CGRect(x: min(max(unit.minX, 0), 1 - unit.width),
                                             y: min(max(unit.minY, 0), 1 - unit.height),
                                             width: unit.width, height: unit.height)
            lastDrop = pickerOpen ? "Let go outside the picker's targets, so the window stays where you put it." : nil
        }
        holdWork?.cancel(); holdWork = nil
        strip.reset()
        dragging = nil
        pointer = nil
        withAnimation(NotchMotion.fast) { target = nil }
        withAnimation(NotchMotion.close) { pickerOpen = false }
    }

}

/// The picker, on the one morphing notch surface.
extension FirstRunSnapDemo {
    fileprivate func picker(_ g: SetupSnapPicker) -> some View {
        let notch = NotchGeometry.standardNotchSize
        let open = pickerOpen
        let width = open ? g.frame.width : stripShown ? stripWidth : notch.width
        return ZStack(alignment: .topLeading) {
            if open {
                pickerContent(g).transition(.opacity)
            } else if stripShown {
                NotchDragTargetStrip(strip: strip, notchWidth: notch.width,
                                     horizontalInset: m.rootTopRadiusCompact + m.lg)
                    .frame(width: stripWidth, height: notch.height)
                    .foregroundStyle(.white)
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: open ? g.frame.height : notch.height, alignment: .topLeading)
        .background(NotchPalette.surfaceBase)
        .clipShape(NotchShape(topCornerRadius: open ? m.rootTopRadiusExpanded : m.rootTopRadiusCompact,
                              bottomCornerRadius: open ? m.rootBottomRadiusExpanded : m.rootBottomRadiusCompact))
        .shadow(color: open ? NotchPalette.panelShadow : .clear,
                radius: NotchPalette.panelShadowRadius, y: NotchPalette.panelShadowY)
        .offset(x: open ? g.frame.minX : g.stageWidth / 2 - width / 2)
        .animation(stripShown ? NotchMotion.open : NotchMotion.close, value: stripShown)
        .allowsHitTesting(false)
    }

    private func pickerContent(_ g: SetupSnapPicker) -> some View {
        let left = g.frame.minX
        let top = g.familyTile(0).minY
        return ZStack(alignment: .topLeading) {
            SetupCameraStrip(title: "Windows")
                .padding(.horizontal, m.rootTopRadiusExpanded + m.lg)
                .frame(width: g.stripSpansShape ? g.frame.width : g.familyWidth)
                .offset(x: g.stripSpansShape ? 0 : g.wingWidth)
            ForEach(Array(pairings.enumerated()), id: \.offset) { p, pairing in
                SetupPairTile(pairing: pairing, dragged: draggedApp, active: target == .pair(p), picker: g)
                    .offset(x: g.pairTile(p).minX - left, y: top)
            }
            if !pairings.isEmpty { seam(at: g.seamX - left, top: top, g: g) }
            if !lesson.presets.isEmpty { seam(at: g.presetSeamX - left, top: top, g: g) }
            ForEach(Array(lesson.presets.enumerated()), id: \.offset) { k, preset in
                SetupPresetTile(preset: preset, active: target == .preset(k), picker: g)
                    .offset(x: g.presetTile(k).minX - left, y: top)
            }
            ForEach(Array(lesson.barLayouts.enumerated()), id: \.element.id) { i, layout in
                SetupSnapTile(layout: layout, activeBox: activeBox(in: i), picker: g)
                    .offset(x: g.familyTile(i).minX - left, y: top)
            }
            Text(caption)
                .notchText(.label)
                .foregroundStyle(target == nil ? NotchPalette.fgSecondary : NotchPalette.fgPrimary)
                .frame(width: g.familyWidth, height: 22)
                .offset(x: g.wingWidth, y: top + g.tile.height + 27)
        }
        .frame(width: g.frame.width, height: g.frame.height, alignment: .topLeading)
    }

    private func seam(at x: CGFloat, top: CGFloat, g: SetupSnapPicker) -> some View {
        RoundedRectangle(cornerRadius: m.radiusSurface).fill(NotchPalette.strokeContrast)
            .frame(width: m.thick, height: g.tile.height + 17)
            .offset(x: x - m.thick / 2, y: top)
    }

    private func activeBox(in layout: Int) -> Int? {
        if case .box(let l, let b)? = target, l == layout { return b }
        return nil
    }

    private var caption: String {
        switch target {
        case .box(let l, let b)?: return "\(lesson.barLayouts[l].name) · box \(b + 1)"
        case .pair(let p)?: return pairings[p].label(dragged: draggedApp)
        case .preset(let k)?: return "\(lesson.presets[k].name) · \(lesson.presets[k].detail)"
        case nil: return "Drag onto a layout box to snap"
        }
    }
}
#endif
