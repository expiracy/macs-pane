import Foundation

/// The user's own layouts and which layouts the drag-to-top picker offers. Presets live beside it in
/// `MacsPaneConfig.presets`.
public struct WindowsConfig: Codable, Equatable, Sendable {
    /// The drag-to-top bar a new config offers: five layouts. There is no cap, offer more and the
    /// picker's row widens, staying centred.
    public static let defaultDragBarLayoutIDs = ["halves", "twoThirds", "thirds", "quarters", "fill"]
    /// The default before 2026-10-22, pinned so a config still on it can be moved to the five.
    static let legacyDefaultDragBarLayoutIDs = ["halves", "quarters", "fill"]

    public var enabled: Bool
    public var layouts: [WindowLayout]
    public var dragBarLayoutIDs: [String]
    /// Whether drawing a layout snaps its boxes to the fine grid (`WindowDrawGrid`).
    public var drawGrid: Bool

    public init(enabled: Bool = true,
                layouts: [WindowLayout] = [],
                dragBarLayoutIDs: [String] = WindowsConfig.defaultDragBarLayoutIDs,
                drawGrid: Bool = false) {
        self.enabled = enabled
        self.layouts = layouts
        self.dragBarLayoutIDs = dragBarLayoutIDs
        self.drawGrid = drawGrid
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WindowsConfig()
        self.enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        self.layouts = (try? c.decodeIfPresent([LossyDecoded<WindowLayout>].self, forKey: .layouts))?
            .compactMap(\.value).filter { !$0.boxes.isEmpty } ?? d.layouts
        self.dragBarLayoutIDs = (try? c.decodeIfPresent([String].self, forKey: .dragBarLayoutIDs))
            ?? d.dragBarLayoutIDs
        self.drawGrid = (try? c.decodeIfPresent(Bool.self, forKey: .drawGrid)) ?? d.drawGrid
    }

    /// Built-in shapes plus the user's own, the layouts the bar can offer.
    public var layoutCatalog: [WindowLayout] { WindowLayout.builtIns + layouts }

    /// Unknown ids are ignored; an intentionally empty bar offers no snap targets.
    public var resolvedDragBarLayouts: [WindowLayout] {
        let catalog = layoutCatalog
        return WindowDragBarEditor.pruned(dragBarLayoutIDs, catalog: catalog)
            .compactMap { id in catalog.first { $0.id == id } }
    }

    public func offersInBar(_ id: String) -> Bool { dragBarLayoutIDs.contains(id) }

    /// A bar still on the old three-layout default becomes the five; a bar anyone chose is left alone.
    /// A default-*value* change keyed off the old value, so it is one-shot and idempotent.
    public mutating func adoptFiveLayoutDefault() {
        if dragBarLayoutIDs == Self.legacyDefaultDragBarLayoutIDs { dragBarLayoutIDs = Self.defaultDragBarLayoutIDs }
    }
}

/// An empty arrangement of boxes. Presets bind windows to boxes; layouts describe only geometry.
public struct WindowLayout: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var boxes: [SnapRegion]
    /// The layer each box was drawn into, parallel to `boxes`. Empty (or short) for layouts saved
    /// before layers, and for the built-ins: those boxes take the draw-order rule instead.
    public var boxLayers: [Int]

    public init(id: String = UUID().uuidString, name: String, boxes: [SnapRegion], boxLayers: [Int] = []) {
        self.id = id
        self.name = name
        self.boxes = boxes
        self.boxLayers = boxLayers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        self.name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Layout"
        self.boxes = (try? c.decodeIfPresent([LossyDecoded<SnapRegion>].self, forKey: .boxes))?
            .compactMap(\.value) ?? []
        self.boxLayers = (try? c.decodeIfPresent([Int].self, forKey: .boxLayers)) ?? []
    }

    /// Every box's layer: the stored one, else the draw-order rule.
    public var layers: [Int] {
        WindowBoxLayers.resolve(boxes.map(\.unitRect), stored: boxLayers.map { Optional($0) })
            .map { $0 ?? 0 }
    }

    /// Add a box, giving it the layer below whatever it was drawn over.
    public mutating func appendBox(_ region: SnapRegion) {
        let current = layers
        let layer = WindowBoxLayers.layerForNewBox(region.unitRect, over: boxes.map(\.unitRect), layers: current)
        boxes.append(region)
        boxLayers = current + [layer]
    }

    /// Take a box out, and its layer with it.
    public mutating func removeBox(at index: Int) {
        guard boxes.indices.contains(index) else { return }
        let current = layers
        boxes.remove(at: index)
        boxLayers = current.enumerated().filter { $0.offset != index }.map(\.element)
    }

    /// Put one box on another layer; every other box keeps the layer it has now.
    public mutating func setLayer(_ layer: Int, ofBox index: Int) {
        guard boxes.indices.contains(index) else { return }
        var current = layers
        current[index] = max(0, layer)
        boxLayers = current
    }

    /// The box drawn under a normalized pointer inside the drag-bar mini display.
    public func boxIndex(atTopLeftUnit point: CGPoint) -> Int? {
        let appKitPoint = CGPoint(x: point.x, y: 1 - point.y)
        return boxes.firstIndex { $0.unitRect.contains(appKitPoint) }
    }

    /// Fixed shapes from the approved draft. Coordinates use AppKit's bottom-left unit screen.
    public static let builtIns: [WindowLayout] = {
        func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> SnapRegion {
            .custom(NormalizedRect(x: x, y: y, width: w, height: h))
        }
        return [
            WindowLayout(id: "halves", name: "Halves", boxes: [box(0, 0, 0.5, 1), box(0.5, 0, 0.5, 1)]),
            WindowLayout(id: "twoThirds", name: "Two thirds", boxes: [box(0, 0, 2.0 / 3, 1), box(2.0 / 3, 0, 1.0 / 3, 1)]),
            WindowLayout(id: "thirds", name: "Thirds", boxes: [
                box(0, 0, 1.0 / 3, 1), box(1.0 / 3, 0, 1.0 / 3, 1), box(2.0 / 3, 0, 1.0 / 3, 1)
            ]),
            WindowLayout(id: "quarters", name: "Quarters", boxes: [
                box(0, 0.5, 0.5, 0.5), box(0.5, 0.5, 0.5, 0.5),
                box(0, 0, 0.5, 0.5), box(0.5, 0, 0.5, 0.5)
            ]),
            WindowLayout(id: "centre", name: "Centre", boxes: [box(0.25, 0.04, 0.5, 0.92)]),
            WindowLayout(id: "fill", name: "Fill", boxes: [box(0, 0, 1, 1)])
        ]
    }()
}
