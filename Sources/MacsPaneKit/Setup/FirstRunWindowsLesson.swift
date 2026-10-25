#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// The sample desktop the drag practice moves windows on, and what its notch offers: your own layouts
/// and hold time, two sample presets, and pairings of the sample apps. The apps are ones every Mac has,
/// so the practice notch, the app's own, draws them with their real icons. Nothing on the Mac moves.
final class WindowsLessonModel: ObservableObject {
    struct App: Hashable {
        let name: String
        let bundleID: String
        /// Drawn when the app's icon can't be found.
        let symbol: String
    }

    struct Window: Identifiable, Equatable {
        var id: String { app.name }
        let app: App
        /// Top-left unit rect of the screen below the menu bar.
        var frame: CGRect
    }

    static let apps = [App(name: "Safari", bundleID: "com.apple.Safari", symbol: "safari"),
                       App(name: "Mail", bundleID: "com.apple.mail", symbol: "envelope.fill"),
                       App(name: "Notes", bundleID: "com.apple.Notes", symbol: "note.text"),
                       App(name: "Music", bundleID: "com.apple.Music", symbol: "music.note")]
    static let scattered: [Window] = [
        Window(app: apps[0], frame: CGRect(x: 0.05, y: 0.30, width: 0.40, height: 0.62)),
        Window(app: apps[2], frame: CGRect(x: 0.55, y: 0.18, width: 0.36, height: 0.55)),
    ]
    /// The practice screen in the coordinates the picker places windows in (AppKit, bottom-left).
    static let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 945)

    /// Two presets of the sample apps, for the notch's right island.
    static let presets: [SnapLayout] = {
        func preset(_ name: String, _ layoutID: String, _ apps: [App]) -> SnapLayout {
            let layout = WindowLayout.builtIns.first { $0.id == layoutID } ?? WindowLayout.builtIns[0]
            var preset = WindowPresetBuilder.make(from: layout, name: name)
            for (slot, app) in apps.enumerated() where preset.slots.indices.contains(slot) {
                preset.slots[slot].binding = .app(bundleID: app.bundleID)
            }
            return preset
        }
        return [preset("Work desk", "halves", [apps[0], apps[1]]), preset("Writing", "twoThirds", [apps[2], apps[3]])]
    }()

    /// The practice notch's settings: the user's layouts and hold time, with the sample presets.
    static func config(from app: MacsPaneConfig) -> MacsPaneConfig {
        var config = app
        config.presets = presets
        return config
    }

    let config: MacsPaneConfig
    @Published var windows: [Window] = scattered
    @Published var progress: Set<Progress> = []

    enum Progress: Hashable { case pickerOpened, aimed, snapped }

    init(config app: MacsPaneConfig) {
        config = Self.config(from: app)
    }

    /// The layouts the notch offers, by name, in its order.
    var offeredLayoutNames: [String] {
        let offered = Set(config.windows.dragBarLayoutIDs)
        return config.windows.layoutCatalog.filter { offered.contains($0.id) }.map(\.name)
    }

    /// The left island's pairings for `dragged`, as the app suggests them: it beside another app, then
    /// with two more.
    func pairings(for dragged: App) -> [ResolvedDragSuggestion] {
        let others = Self.apps.filter { $0 != dragged && $0.name != "Notes" }
        guard others.count >= 2 else { return [] }
        let sets: [([App], [CGRect])] = [
            ([dragged, others[0]], [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]),
            ([dragged, others[0], others[1]], [CGRect(x: 0, y: 0, width: 0.5, height: 1),
                                               CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                                               CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)]),
        ]
        return sets.map { apps, frames in
            let placements = zip(apps, frames).map { app, unit in
                WindowTilePlacement(window: Self.window(app), frame: Self.screenFrame(unit))
            }
            return ResolvedDragSuggestion(pairing: DragPairing(placements: placements),
                                          icons: apps.map { SnapAppIcons.icon(bundleID: $0.bundleID) },
                                          label: apps.map(\.name).joined(separator: " + "))
        }
    }

    // MARK: - Moving the sample windows

    /// `app`'s window to `unit` (top-left), opening it there if it isn't on the desktop yet.
    func place(_ app: App, at unit: CGRect) {
        if let i = windows.firstIndex(where: { $0.app == app }) { windows[i].frame = unit } else {
            windows.append(Window(app: app, frame: unit))
        }
    }

    /// A pairing's windows, each to its place.
    func apply(_ placements: [WindowTilePlacement]) {
        for placement in placements {
            guard let app = Self.apps.first(where: { Self.window($0).id == placement.window.id }) else { continue }
            place(app, at: Self.unit(placement.frame))
        }
    }

    /// Opening a preset puts each of its apps in its box; other windows stay put.
    func apply(presetID: String) {
        guard let preset = config.presets.first(where: { $0.id == presetID }) else { return }
        for slot in preset.slots where !slot.isRemoved {
            guard case let .app(bundleID) = slot.binding,
                  let app = Self.apps.first(where: { $0.bundleID == bundleID }) else { continue }
            place(app, at: Self.topLeft(slot.region))
        }
    }

    func scatter() { windows = Self.scattered }

    // MARK: - Coordinates

    /// A sample app's stand-in for a window-server window.
    private static func window(_ app: App) -> ProcessWindowInfo {
        let id = UInt32((apps.firstIndex(of: app) ?? 0) + 1)
        return ProcessWindowInfo(id: id, ownerPid: 0, title: app.name, frame: .zero, isOnScreen: true, layer: 0, alpha: 1)
    }

    /// A frame on the practice screen as a top-left unit rect.
    static func unit(_ frame: CGRect) -> CGRect { ResolvedDragSuggestion.unitRect(frame, in: visibleFrame) }

    /// A top-left unit rect as a frame on the practice screen.
    private static func screenFrame(_ unit: CGRect) -> CGRect {
        CGRect(x: visibleFrame.minX + unit.minX * visibleFrame.width,
               y: visibleFrame.minY + (1 - unit.maxY) * visibleFrame.height,
               width: unit.width * visibleFrame.width, height: unit.height * visibleFrame.height)
    }

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
            HStack(spacing: 6) {
                if let icon = SnapAppIcons.icon(bundleID: app.bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } else {
                    Image(systemName: app.symbol)
                }
                Text(app.name)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(lifted ? 0.35 : 0.18), radius: lifted ? 8 : 3, y: lifted ? 4 : 1)
    }
}
#endif
