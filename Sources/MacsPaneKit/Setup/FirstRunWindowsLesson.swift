#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// The Windows step: practise dragging a window to the notch, then read what feeds the picker it
/// opens — layouts (and your own), and presets. Local practice only — no real window moves.
struct FirstRunWindowsLesson: View {
    @StateObject private var lesson: WindowsLessonModel

    init(lesson: WindowsLessonModel = WindowsLessonModel()) {
        self._lesson = StateObject(wrappedValue: lesson)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FirstRunSnapDemo(lesson: lesson)
            VStack(alignment: .leading, spacing: 10) {
                explainer("rectangle.split.2x1", "Layouts",
                          "The picker shows the layouts in your drag-to-top bar. On the Windows tab you choose which ones "
                          + "it offers, as many as you like, and add your own by drawing boxes on an empty screen.")
                explainer("square.stack.3d.up", "Presets",
                          "A preset fills a layout's boxes with the apps you choose and opens them all together. Make one "
                          + "on the Windows tab, from a layout or from the desktop as it is.")
            }
            Spacer(minLength: 0)
            Label("Moving windows needs Accessibility, which the next step offers. Every other tab works without it.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
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

/// The sample desktop the drag practice moves windows on, and the picker's contents.
final class WindowsLessonModel: ObservableObject {
    struct App: Hashable {
        let name: String
        let symbol: String
        let tint: Color
    }

    struct Window: Identifiable, Equatable {
        var id: String { app.name }
        let app: App
        /// Top-left unit rect of the screen below the menu bar.
        var frame: CGRect
    }

    /// A recent-pair tile: the dragged window plus apps used alongside it, each with its place.
    struct Pairing {
        let partners: [App]
        /// Frames in slot order; slot 0 is the dragged window.
        let frames: [CGRect]

        func label(dragged: App) -> String { ([dragged] + partners).map(\.name).joined(separator: " + ") }
    }

    /// A saved preset: a layout and the app that fills each box.
    struct Preset {
        let name: String
        let layout: WindowLayout
        let apps: [App]

        var detail: String { apps.map(\.name).joined(separator: " + ") }
    }

    static let apps = [App(name: "Browser", symbol: "globe", tint: .blue),
                       App(name: "Mail", symbol: "envelope.fill", tint: .cyan),
                       App(name: "Notes", symbol: "note.text", tint: .orange),
                       App(name: "Music", symbol: "music.note", tint: .pink)]
    static let scattered: [Window] = [
        Window(app: apps[0], frame: CGRect(x: 0.05, y: 0.30, width: 0.40, height: 0.62)),
        Window(app: apps[2], frame: CGRect(x: 0.55, y: 0.18, width: 0.36, height: 0.55)),
    ]

    /// The five layouts a fresh drag-to-top bar offers, so the practice picker looks as the real one will.
    let barLayouts: [WindowLayout] = ["halves", "twoThirds", "thirds", "quarters", "fill"].compactMap { id in
        WindowLayout.builtIns.first { $0.id == id }
    }
    /// Setup-only: the practice picker shows two saved presets in a wing on its right. The shipped picker
    /// does not offer presets; the demo shows where they come from.
    let presets: [Preset] = {
        let layout = { (id: String) in WindowLayout.builtIns.first { $0.id == id } ?? WindowLayout.builtIns[0] }
        return [Preset(name: "Work desk", layout: layout("halves"), apps: [apps[0], apps[1]]),
                Preset(name: "Writing", layout: layout("twoThirds"), apps: [apps[2], apps[3]])]
    }()
    @Published var windows: [Window] = scattered
    @Published var progress: Set<Progress> = []
    /// Offscreen-render seeds only: draw the drag picker open with a box, or a pair, aimed at.
    let previewAim: Bool
    let previewAimPair: Bool
    let previewStrip: Bool
    /// How long a window is held still on the strip before the layouts open: the user's own notch dwell.
    let holdDelay: TimeInterval

    enum Progress: Hashable { case pickerOpened, aimed, snapped }

    init(snapped: Bool = false, aim: Bool = false, aimPair: Bool = false, strip: Bool = false,
         holdDelay: TimeInterval = 0.3) {
        previewStrip = strip
        self.holdDelay = holdDelay
        previewAim = aim
        previewAimPair = aimPair
        if snapped {
            windows = [Window(app: Self.apps[0], frame: Self.topLeft(WindowLayout.builtIns[0].boxes[0])),
                       Window(app: Self.apps[2], frame: Self.topLeft(WindowLayout.builtIns[0].boxes[1]))]
            progress = [.pickerOpened, .aimed, .snapped]
        }
    }

    /// Two suggestions, as the picker's wing holds at most: a pair, then a trio.
    func pairings(for dragged: App) -> [Pairing] {
        let others = Self.apps.filter { $0 != dragged && $0.name != "Notes" }
        guard others.count >= 2 else { return [] }
        return [Pairing(partners: [others[0]],
                        frames: [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]),
                Pairing(partners: [others[0], others[1]],
                        frames: [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                                 CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)])]
    }

    /// The dragged window takes slot 0; each partner opens (or moves) into its own slot.
    func apply(_ pairing: Pairing, dragged: App) {
        for (slot, app) in ([dragged] + pairing.partners).enumerated() {
            let frame = pairing.frames[slot]
            if let i = windows.firstIndex(where: { $0.app == app }) { windows[i].frame = frame } else {
                windows.append(Window(app: app, frame: frame))
            }
        }
    }

    /// Opening a preset puts each of its apps in its box; other windows stay put.
    func apply(_ preset: Preset) {
        for (box, app) in preset.apps.enumerated() where preset.layout.boxes.indices.contains(box) {
            let frame = Self.topLeft(preset.layout.boxes[box])
            if let i = windows.firstIndex(where: { $0.app == app }) { windows[i].frame = frame } else {
                windows.append(Window(app: app, frame: frame))
            }
        }
    }

    func scatter() { windows = Self.scattered }

    /// A layout box (AppKit bottom-left unit space) in the top-left unit space the drawings use.
    static func topLeft(_ region: SnapRegion) -> CGRect {
        let r = region.unitRect
        return CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }
}

/// A sample app window on the sketched desktop: grey title bar with the three dots, the app in the middle.
struct SetupSampleWindow: View {
    let app: WindowsLessonModel.App
    var lifted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.black.opacity(0.18)).frame(width: 6, height: 6) }
                Spacer()
            }
            .padding(.horizontal, 7)
            .frame(height: 16)
            .background(Color(white: 0.9))
            Label(app.name, systemImage: app.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(lifted ? 0.35 : 0.18), radius: lifted ? 8 : 3, y: lifted ? 4 : 1)
    }
}

/// An app's icon as the picker's pair tiles show one: its glyph on its own colour.
struct SetupAppIcon: View {
    let app: WindowsLessonModel.App
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: app.symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(app.tint.gradient))
    }
}
#endif
