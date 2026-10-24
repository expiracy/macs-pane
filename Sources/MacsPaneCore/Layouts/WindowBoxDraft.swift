import CoreGraphics
import Foundation

/// A layout or preset while it is being drawn on screen: its name and its boxes, each with what fills
/// it. One editor draws both, a layout is boxes alone; a preset is the same boxes with an app in each.
///
/// Boxes live in the drawing's own space: top-left unit coordinates of the screen's visible frame (the
/// space `WindowDrawGrid` works in). They become `SnapRegion`s, which are bottom-left, only when saved.
public struct WindowBoxDraft: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case layout, preset }

    public struct Box: Equatable, Sendable, Identifiable {
        public let id: String
        /// Top-left unit rect of the visible screen.
        public var rect: CGRect
        /// What fills the box when the preset is applied. Always `.empty` in a layout.
        public var binding: SnapBinding
        /// For an app: open it when the preset is applied and it isn't running.
        public var launchIfClosed: Bool
        /// The layer the box was drawn into (`WindowBoxLayers`); lower is nearer the front.
        public var layer: Int

        public init(id: String = UUID().uuidString, rect: CGRect, binding: SnapBinding = .empty,
                    launchIfClosed: Bool = true, layer: Int = 0) {
            self.id = id
            self.rect = rect
            self.binding = binding
            self.launchIfClosed = launchIfClosed
            self.layer = layer
        }
    }

    /// A drag shorter than this either way is a click, not a box.
    public static let minimumSide: CGFloat = 0.04

    public let kind: Kind
    /// The saved layout or preset this edits; nil for a new one.
    public let editingID: String?
    public var name: String
    public private(set) var boxes: [Box]
    /// The box the pointer last picked, which ⌫ removes.
    public var selection: String?

    public init(kind: Kind, editingID: String? = nil, name: String = "", boxes: [Box] = []) {
        self.kind = kind
        self.editingID = editingID
        self.name = name
        self.boxes = boxes
    }

    /// A saved layout, ready to change.
    public init(layout: WindowLayout) {
        let layers = layout.layers
        self.init(kind: .layout, editingID: layout.id, name: layout.name,
                  boxes: layout.boxes.enumerated().map { index, region in
                      Box(rect: Self.topLeft(region), layer: layers[index])
                  })
    }

    /// A saved preset, ready to change. Boxes the preset had left out stay out.
    public init(preset: SnapLayout) {
        let layers = WindowPresetBuilder.layers(of: preset)
        let boxes = preset.slots.indices.filter { !preset.slots[$0].isRemoved }.map { index in
            let slot = preset.slots[index]
            return Box(rect: Self.topLeft(slot.region), binding: slot.binding,
                       launchIfClosed: slot.launchIfClosed, layer: layers[index] ?? 0)
        }
        self.init(kind: .preset, editingID: preset.id, name: preset.name, boxes: boxes)
    }

    // MARK: - Reading

    public var isNew: Bool { editingID == nil }

    /// A layout needs a box; a preset needs a box with something to put in it.
    public var canSave: Bool {
        switch kind {
        case .layout: return !boxes.isEmpty
        case .preset: return boxes.contains { $0.binding != .empty }
        }
    }

    public var selectedBox: Box? { boxes.first { $0.id == selection } }

    public func box(_ id: String) -> Box? { boxes.first { $0.id == id } }

    /// The box under a point, as drawn: the front-most layer wins, then the one drawn last.
    public func box(at point: CGPoint) -> Box? {
        boxes.enumerated()
            .filter { $0.element.rect.contains(point) }
            .min { a, b in
                a.element.layer != b.element.layer ? a.element.layer < b.element.layer : a.offset > b.offset
            }?.element
    }

    /// The boxes in the order to draw them: deepest layer first, so the front ones paint over it.
    public var paintOrder: [Box] {
        boxes.enumerated()
            .sorted { a, b in a.element.layer != b.element.layer ? a.element.layer > b.element.layer : a.offset < b.offset }
            .map(\.element)
    }

    // MARK: - Drawing

    /// The box a drag from `start` to `end` draws: added in the layer below whatever it covers, and
    /// selected. Nil (and nothing added) when the drag was too short to mean a box.
    @discardableResult
    public mutating func draw(from start: CGPoint, to end: CGPoint, grid: Bool) -> Box? {
        let rect = WindowDrawGrid.rect(from: start, to: end, grid: grid)
        guard rect.width >= Self.minimumSide, rect.height >= Self.minimumSide else { return nil }
        let layer = WindowBoxLayers.layerForNewBox(rect, over: boxes.map(\.rect), layers: boxes.map(\.layer))
        let box = Box(rect: rect, binding: .empty, layer: layer)
        boxes.append(box)
        selection = box.id
        return box
    }

    /// Move a box from where the drag picked it up (`start`) by the drag so far.
    public mutating func move(_ id: String, from start: CGRect, by delta: CGSize, grid: Bool) {
        update(id) { $0.rect = WindowDrawGrid.moved(start, by: delta, grid: grid) }
    }

    /// Resize a box from where the drag picked it up (`start`) by pulling `edges`.
    public mutating func resize(_ id: String, from start: CGRect, edges: WindowDrawGrid.Edges, by delta: CGSize,
                                grid: Bool) {
        update(id) { $0.rect = WindowDrawGrid.resized(start, edges: edges, by: delta, grid: grid) }
    }

    public mutating func remove(_ id: String) {
        boxes.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }

    public mutating func removeSelected() {
        if let selection { remove(selection) }
    }

    public mutating func bind(_ binding: SnapBinding, to id: String) {
        update(id) { $0.binding = binding }
    }

    public mutating func setLaunchIfClosed(_ launch: Bool, for id: String) {
        update(id) { $0.launchIfClosed = launch }
    }

    /// Start again from other boxes, a built-in layout, the windows on screen, or none. Bindings line up
    /// with `regions`; missing ones are empty.
    public mutating func replaceBoxes(with regions: [SnapRegion], bindings: [SnapBinding] = []) {
        let layers = WindowBoxLayers.resolve(regions.map(\.unitRect))
        boxes = regions.enumerated().map { index, region in
            Box(rect: Self.topLeft(region),
                binding: kind == .preset && bindings.indices.contains(index) ? bindings[index] : .empty,
                layer: layers[index] ?? 0)
        }
        selection = nil
    }

    private mutating func update(_ id: String, _ change: (inout Box) -> Void) {
        guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
        change(&boxes[index])
    }

    // MARK: - Saving

    /// The boxes as a layout's regions and layers.
    public var regions: [SnapRegion] { boxes.map { Self.region($0.rect) } }

    /// A layout with these boxes, keeping the edited layout's id.
    public func layout(named name: String) -> WindowLayout {
        WindowLayout(id: editingID ?? UUID().uuidString, name: name, boxes: regions, boxLayers: boxes.map(\.layer))
    }

    /// The preset's slots, one per box.
    public var slots: [SnapLayoutSlot] {
        boxes.map { box in
            SnapLayoutSlot(region: Self.region(box.rect), binding: box.binding,
                           launchIfClosed: box.launchIfClosed, layer: box.layer)
        }
    }

    // MARK: - Spaces

    /// A saved region in the drawing's top-left unit space.
    public static func topLeft(_ region: SnapRegion) -> CGRect {
        let r = region.unitRect
        return CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }

    /// A drawn rect as a saved region (bottom-left). Exact, so opening a preset and saving it unchanged
    /// keeps every box where it was.
    public static func region(_ rect: CGRect) -> SnapRegion {
        .custom(NormalizedRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height))
    }
}
