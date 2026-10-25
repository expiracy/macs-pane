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
    /// Built-in layouts deleted from the menu, by id; the menu can bring them all back.
    public var deletedBuiltIns: [String] = []
    /// The order the menu lists layouts in, as the user dragged them. Empty until they first do;
    /// layouts it does not name follow in the default order.
    public var layoutOrder: [String]

    public init(enabled: Bool = true,
                layouts: [WindowLayout] = [],
                dragBarLayoutIDs: [String] = WindowsConfig.defaultDragBarLayoutIDs,
                drawGrid: Bool = true,
                layoutOrder: [String] = []) {
        self.enabled = enabled
        self.layouts = layouts
        self.dragBarLayoutIDs = dragBarLayoutIDs
        self.drawGrid = drawGrid
        self.layoutOrder = layoutOrder
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
        self.layoutOrder = (try? c.decodeIfPresent([String].self, forKey: .layoutOrder)) ?? d.layoutOrder
        self.deletedBuiltIns = (try? c.decodeIfPresent([String].self, forKey: .deletedBuiltIns)) ?? d.deletedBuiltIns
    }

    /// Built-in shapes (less any deleted) plus the user's own, the layouts the bar can offer, in the
    /// user's order.
    public var layoutCatalog: [WindowLayout] {
        let builtIns = WindowLayout.builtIns.filter { !deletedBuiltIns.contains($0.id) }
        return ListOrder.sorted(builtIns + layouts, by: layoutOrder)
    }

    /// Unknown ids are ignored; an intentionally empty bar offers no snap targets.
    public var resolvedDragBarLayouts: [WindowLayout] {
        let catalog = layoutCatalog
        return WindowDragBarEditor.pruned(dragBarLayoutIDs, catalog: catalog)
            .compactMap { id in catalog.first { $0.id == id } }
    }

    public func offersInBar(_ id: String) -> Bool { dragBarLayoutIDs.contains(id) }

    /// Drag a layout to another place in the list. The notch offers its layouts in the list's order,
    /// so the bar is put in that order too.
    public mutating func moveLayout(from source: Int, to destination: Int) {
        var ids = layoutCatalog.map(\.id)
        ListOrder.move(from: source, to: destination, in: &ids)
        layoutOrder = ids
        let offered = Set(dragBarLayoutIDs)
        dragBarLayoutIDs = ids.filter(offered.contains)
    }

    /// A layout deleted from the menu, yours or a built-in, with its place in the list and in the
    /// notch, so it can be put back exactly.
    public struct RemovedLayout: Equatable, Sendable {
        public let layout: WindowLayout
        public let index: Int
        public let barIndex: Int?
        public let layoutOrder: [String]
    }

    /// Delete a layout, out of the notch too. One of yours is removed; a built-in is set aside in
    /// `deletedBuiltIns`. Nil when no layout in the list has that id.
    public mutating func removeLayout(_ id: String) -> RemovedLayout? {
        let barIndex = dragBarLayoutIDs.firstIndex(of: id)
        let removed: RemovedLayout
        if let index = layouts.firstIndex(where: { $0.id == id }) {
            removed = RemovedLayout(layout: layouts[index], index: index, barIndex: barIndex, layoutOrder: layoutOrder)
            layouts.remove(at: index)
        } else if let builtIn = WindowLayout.builtIns.first(where: { $0.id == id }), !deletedBuiltIns.contains(id) {
            removed = RemovedLayout(layout: builtIn, index: 0, barIndex: barIndex, layoutOrder: layoutOrder)
            deletedBuiltIns.append(id)
        } else {
            return nil
        }
        dragBarLayoutIDs.removeAll { $0 == id }
        layoutOrder.removeAll { $0 == id }
        return removed
    }

    /// Bring back every deleted built-in, in its default place and out of the notch.
    public mutating func restoreBuiltIns() { deletedBuiltIns = [] }

    public mutating func restore(_ removed: RemovedLayout) {
        let id = removed.layout.id
        if WindowLayout.builtIns.contains(where: { $0.id == id }) {
            guard deletedBuiltIns.contains(id) else { return }
            deletedBuiltIns.removeAll { $0 == id }
        } else {
            guard !layouts.contains(where: { $0.id == id }) else { return }
            layouts.insert(removed.layout, at: min(removed.index, layouts.count))
        }
        if let bar = removed.barIndex { dragBarLayoutIDs.insert(id, at: min(bar, dragBarLayoutIDs.count)) }
        layoutOrder = removed.layoutOrder
    }

    /// Put a layout in the bar or take it out. One put in lands where it sits in the list, so the
    /// notch and the menu read in the same order.
    @discardableResult
    public mutating func toggleInBar(_ id: String) -> WindowDragBarEditor.ToggleResult {
        let catalog = layoutCatalog
        guard !dragBarLayoutIDs.contains(id) else {
            return WindowDragBarEditor.toggle(id, in: &dragBarLayoutIDs, catalog: catalog)
        }
        let before = Set(catalog.prefix { $0.id != id }.map(\.id))
        let index = dragBarLayoutIDs.lastIndex(where: before.contains).map { $0 + 1 } ?? 0
        return WindowDragBarEditor.insert(id, at: index, in: &dragBarLayoutIDs, catalog: catalog)
    }

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
