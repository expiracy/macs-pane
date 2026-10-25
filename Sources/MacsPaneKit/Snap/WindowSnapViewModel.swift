#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// Drives window-snap mode: a transient overlay on the expanded notch (not a `NotchPanelKind` tab,
/// it's drag-driven and the user never selects it). The `WindowSnapController` feeds it the live
/// drag; it decides the highlighted zone from the pointer over the picker tiles and hands back the
/// target frame on release. Owned by `MacsPaneSnapHost` so its state survives panel
/// rebuilds. Holds no window, the ghost overlay panel is the controller's, mirroring how
/// the host owns no `NSPanel`.
final class WindowSnapViewModel: ObservableObject {
    /// True while a window drag is being tracked for snapping, gates the picker in `MacsPaneNotchView`.
    @Published private(set) var isSnapping = false
    /// The zone the pointer is over (the one a release commits). Drives the picker highlight and the
    /// full-screen ghost.
    @Published private(set) var highlightedZone: WindowSnapZone?
    @Published private(set) var highlightedLayoutBox: SnapLayoutBoxTarget?
    @Published private(set) var pickerLayouts: [WindowLayout] = []
    /// The recent-app pairing tiles on the far left of the picker (icon-only mini-layouts). Resolved by
    /// the controller when a drag begins, empty when nothing else is open, so the picker shows zones alone.
    @Published private(set) var suggestions: [ResolvedDragSuggestion] = []
    /// The suggestion tile the pointer is over (mutually exclusive with `highlightedZone`).
    @Published private(set) var highlightedSuggestion: Int?
    /// Your presets on the right island, the first `WindowSnapMetrics.maxPresets` in the menu's order.
    @Published private(set) var presets: [ResolvedPickerPreset] = []
    /// The preset tile the pointer is over.
    @Published private(set) var highlightedPreset: Int?

    private(set) var config: WindowSnapConfig
    /// The visible frame (AppKit bottom-left) of the screen the snap targets, set on `begin`, used
    /// to turn a zone into a concrete frame for both the ghost and the actual move.
    private(set) var visibleFrame: CGRect = .zero
    /// Per-family picker geometry in the notch panel's local space, reported by the view: the whole
    /// tile (to pick which family the pointer is over) and the inner mini-screen box (to map the
    /// pointer onto a cell within that family). The controller maps the drag pointer into this space.
    private var familyFrames: [WindowSnapFamily: SnapTileFrame] = [:]
    private(set) var layoutFrames: [String: SnapTileFrame] = [:]
    /// Suggestion-tile rects (index → whole tile) in the notch panel's local space. The whole tile is one
    /// aim target, releasing anywhere on it commits the pairing, so there's no inner box like the zones.
    private var suggestionFrames: [Int: CGRect] = [:]
    private(set) var presetFrames: [Int: CGRect] = [:]

    init(config: WindowSnapConfig) { self.config = config }

    func apply(config: WindowSnapConfig) { self.config = config }

    func apply(windowConfig: WindowsConfig) {
        pickerLayouts = windowConfig.resolvedDragBarLayouts
    }

    /// Your presets, resolved once here (app icons included) rather than in a view body.
    func apply(presets: [SnapLayout]) {
        let shown = presets.prefix(WindowSnapMetrics.maxPresets)
        guard shown.map(\.id) != self.presets.map(\.id) || shown.map(\.name) != self.presets.map(\.name)
                || shown.map(\.slots) != self.presets.map(\.slots) else { return }
        self.presets = shown.map(ResolvedPickerPreset.init)
    }

    /// The picker's row is exactly the layouts offered, it widens and narrows with the bar, and the
    /// tiles stay packed and centred on the notch.
    var pickerTileCount: Int { max(pickerLayouts.count, 1) }

    /// The families the picker presents, left-to-right. A fixed, symmetric row (Maximize centred),
    /// each tile folds a whole family of zones, so the row stays short whatever the zone count.
    var families: [WindowSnapFamily] { WindowSnapFamily.defaultRow }

    // MARK: - Drag lifecycle (called by WindowSnapController)

    func begin(visibleFrame: CGRect, suggestions: [ResolvedDragSuggestion]) {
        self.visibleFrame = visibleFrame
        self.suggestions = suggestions
        highlightedZone = nil
        highlightedLayoutBox = nil
        highlightedSuggestion = nil
        highlightedPreset = nil
        isSnapping = true
    }

    /// Pointer moved, expressed in the notch panel's local space (converted by the controller). The
    /// islands' tiles and the layout tiles never overlap, so at most one lights.
    func pointerMoved(toPanelLocal point: CGPoint) {
        guard isSnapping else { return }
        let suggestion = suggestionIndex(at: point)
        let preset = suggestion == nil ? presetIndex(at: point) : nil
        if highlightedSuggestion != suggestion { highlightedSuggestion = suggestion }
        if highlightedPreset != preset { highlightedPreset = preset }
        if suggestion != nil || preset != nil {
            if highlightedZone != nil { highlightedZone = nil }
            if highlightedLayoutBox != nil { highlightedLayoutBox = nil }
            return
        }
        let target = layoutBox(at: point)
        if target != highlightedLayoutBox { highlightedLayoutBox = target }
        if highlightedZone != nil { highlightedZone = nil }
    }

    /// Release: what to commit, or `nil` if released over no tile (no-op). A highlighted suggestion tiles
    /// the dragged window plus its partners; otherwise a highlighted zone snaps the dragged window alone.
    /// Deliberately does NOT reset, the controller keeps the picker rendering through the collapse so
    /// the resting tab page never flashes between the selection and the close, then calls `cancel()`
    /// once the close animation has carried the picker off-screen.
    @discardableResult
    func end() -> SnapCommit? {
        if let i = highlightedSuggestion, suggestions.indices.contains(i) {
            return .pairing(suggestions[i].pairing.placements)
        }
        if let i = highlightedPreset, presets.indices.contains(i) {
            return .preset(presets[i].id)
        }
        if let target = highlightedLayoutBox {
            return .layoutBox(target.region.frame(in: visibleFrame))
        }
        guard isSnapping, let z = highlightedZone else { return nil }
        return .zone(z, z.frame(in: visibleFrame))
    }

    /// Drag cancelled / abandoned, collapse with no snap.
    func cancel() { reset() }

    /// Clear the highlight without ending the snap session (e.g. the drag left the notch hot-zone
    /// but is still in progress, re-entering will re-highlight).
    func clearHighlight() {
        if highlightedZone != nil { highlightedZone = nil }
        if highlightedLayoutBox != nil { highlightedLayoutBox = nil }
        if highlightedSuggestion != nil { highlightedSuggestion = nil }
        if highlightedPreset != nil { highlightedPreset = nil }
    }

    private func reset() {
        isSnapping = false
        highlightedZone = nil
        highlightedLayoutBox = nil
        highlightedSuggestion = nil
        highlightedPreset = nil
        suggestions = []
        familyFrames = [:]
        layoutFrames = [:]
        suggestionFrames = [:]
        presetFrames = [:]
    }

    // MARK: - Hit-testing

    /// Stored by the picker view (via a preference) whenever tile geometry changes.
    func setFamilyFrames(_ frames: [WindowSnapFamily: SnapTileFrame]) { familyFrames = frames }
    func setLayoutFrames(_ frames: [String: SnapTileFrame]) { layoutFrames = frames }

    func layoutBox(at panelLocalPoint: CGPoint) -> SnapLayoutBoxTarget? {
        guard let layout = pickerLayouts.first(where: { layoutFrames[$0.id]?.tile.contains(panelLocalPoint) == true }),
              let frame = layoutFrames[layout.id], frame.inner.width > 0, frame.inner.height > 0
        else { return nil }
        let point = CGPoint(x: (panelLocalPoint.x - frame.inner.minX) / frame.inner.width,
                            y: (panelLocalPoint.y - frame.inner.minY) / frame.inner.height)
        guard let index = layout.boxIndex(atTopLeftUnit: point) else { return nil }
        return SnapLayoutBoxTarget(layoutID: layout.id, layoutName: layout.name,
                                   boxIndex: index, region: layout.boxes[index])
    }

    /// Stored by the picker view (via a preference) whenever suggestion-tile geometry changes.
    func setSuggestionFrames(_ frames: [Int: CGRect]) { suggestionFrames = frames }

    /// The suggestion tile under `panelLocalPoint`, or nil if the pointer is over none.
    func suggestionIndex(at panelLocalPoint: CGPoint) -> Int? {
        suggestionFrames.first(where: { $0.value.contains(panelLocalPoint) })?.key
    }

    /// Stored by the picker view (via a preference) whenever preset-tile geometry changes.
    func setPresetFrames(_ frames: [Int: CGRect]) { presetFrames = frames }

    /// The preset tile under `panelLocalPoint`; the whole tile is one target.
    func presetIndex(at panelLocalPoint: CGPoint) -> Int? {
        presetFrames.first(where: { $0.value.contains(panelLocalPoint) })?.key
    }

    /// The zone under `panelLocalPoint`: the family whose tile contains it, then the sub-zone the
    /// pointer is aimed at *within* that family's mini-screen. `nil` if the pointer is over no tile.
    func zone(at panelLocalPoint: CGPoint) -> WindowSnapZone? {
        guard let (family, frame) = familyFrames.first(where: { $0.value.tile.contains(panelLocalPoint) }) else {
            return nil
        }
        let box = frame.inner
        guard box.width > 0, box.height > 0 else { return family.members.first }
        let normalized = CGPoint(x: (panelLocalPoint.x - box.minX) / box.width,
                                 y: (panelLocalPoint.y - box.minY) / box.height)
        return family.zone(atNormalized: normalized)
    }

    /// The full-screen ghost frame (AppKit coords) for the current highlight, if previews are on.
    var previewFrame: CGRect? {
        guard config.showFullScreenPreview else { return nil }
        if let target = highlightedLayoutBox { return target.region.frame(in: visibleFrame) }
        return highlightedZone?.frame(in: visibleFrame)
    }
}

/// A family tile's geometry in the notch panel's local space, reported by `WindowSnapView`: the whole
/// `tile` (used to decide which family the pointer is over, forgiving across the tile's padding) and
/// the `inner` mini-screen box the cells are drawn in (used to map the pointer onto a specific cell).
struct SnapTileFrame: Equatable {
    var tile: CGRect
    var inner: CGRect
}

/// What releasing the drag over the picker commits to.
enum SnapCommit {
    /// Snap the dragged window alone to a zone's frame (AppKit bottom-left), today's behavior.
    case zone(WindowSnapZone, CGRect)
    case layoutBox(CGRect)
    /// Tile the dragged window plus recent partners, hand straight to a `WindowArranging`.
    case pairing([WindowTilePlacement])
    /// Apply one of your presets by id, as clicking it in the menu does.
    case preset(String)
}

struct SnapLayoutBoxTarget: Equatable {
    let layoutID: String
    let layoutName: String
    let boxIndex: Int
    let region: SnapRegion
}

/// A drag pairing resolved for display: the Core `DragPairing` plus per-slot app icons and a label,
/// built once by `WindowSnapController` when a drag begins (icons resolved off the render path, never in
/// a SwiftUI body). The picker draws each placement as a glyph cell with its app icon.
struct ResolvedDragSuggestion {
    let pairing: DragPairing
    /// App icon per placement, in slot order (nil if the app has none).
    let icons: [NSImage?]
    /// "Mail + Safari", the tile's name.
    let label: String
}

/// One of your presets as the picker's right island draws it: its boxes (top-left unit rects) and the
/// icon of the app each one opens, resolved once when the presets change.
struct ResolvedPickerPreset {
    let id: String
    let name: String
    let slots: [SnapLayoutSlot]
    let boxes: [SnapGlyphBox]
    /// The apps it opens ("Xcode + Terminal"), shown in place of its name while it is the aim; nil
    /// when none of its boxes has an app chosen.
    let apps: String?

    init(_ preset: SnapLayout) {
        id = preset.id
        name = preset.name
        slots = preset.slots
        let kept = preset.slots.filter { !$0.isRemoved }
        let urls = kept.compactMap { slot -> URL? in
            guard case let .app(bundleID) = slot.binding else { return nil }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }
        let names = urls.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        apps = names.isEmpty ? nil : names.joined(separator: " + ")
        boxes = kept.map { slot in
            let unit = slot.region.unitRect
            let rect = CGRect(x: unit.minX, y: 1 - unit.maxY, width: unit.width, height: unit.height)
            guard case let .app(bundleID) = slot.binding,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { return SnapGlyphBox(rect: rect) }
            return SnapGlyphBox(rect: rect, icon: SnapAppIcons.icon(forAppAt: url))
        }
    }

}
#endif
