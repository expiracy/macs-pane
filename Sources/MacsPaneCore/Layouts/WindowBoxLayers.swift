import CoreGraphics

/// Which layer each box of a layout sits in, and which of those layers a display is drawing.
///
/// A box's layer comes from where it was **drawn**: a box drawn over others goes one layer below the
/// deepest of them, so whatever was there first stays in front. A box that overlaps nothing is on
/// layer 0, so a layout with no overlap has exactly one layer. Once given, a layer is the box's own,
/// it is stored with the box, and moving the box later never renumbers it.
///
/// Layers are 0-based here; the UI says "Layer 1" for layer 0. Lower numbers draw nearer the front.
public enum WindowBoxLayers {
    /// Edges that merely touch (two halves) are not an overlap.
    static let tolerance: CGFloat = 0.0005

    public static func overlap(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX - tolerance && b.minX < a.maxX - tolerance
            && a.minY < b.maxY - tolerance && b.minY < a.maxY - tolerance
    }

    /// The layer for every box. A stored layer wins; a box without one gets the draw-order rule
    /// against the boxes before it. Boxes in `excluded` (left out of a preset) get no layer.
    public static func resolve(_ rects: [CGRect], stored: [Int?] = [], excluded: Set<Int> = []) -> [Int?] {
        var layers: [Int?] = Array(repeating: nil, count: rects.count)
        for index in rects.indices where !excluded.contains(index) {
            if stored.indices.contains(index), let layer = stored[index] {
                layers[index] = max(0, layer)
                continue
            }
            var layer = 0
            for earlier in 0..<index where !excluded.contains(earlier) {
                if let below = layers[earlier], overlap(rects[earlier], rects[index]) {
                    layer = max(layer, below + 1)
                }
            }
            layers[index] = layer
        }
        return layers
    }

    /// The layer a box about to be drawn at `rect` lands in, given the boxes already there.
    public static func layerForNewBox(_ rect: CGRect, over rects: [CGRect], layers: [Int]) -> Int {
        var layer = 0
        for (index, other) in rects.enumerated() where layers.indices.contains(index) && overlap(other, rect) {
            layer = max(layer, layers[index] + 1)
        }
        return layer
    }

    /// How many layers the boxes use, at least one when there is any box at all.
    public static func count(_ layers: [Int?]) -> Int {
        (layers.compactMap { $0 }.max() ?? -1) + 1
    }

    /// Boxes per layer, in layer order.
    public static func boxCounts(_ layers: [Int?]) -> [Int] {
        (0..<count(layers)).map { layer in layers.filter { $0 == layer }.count }
    }

    /// Whether a box is drawn on a display hiding `hidden` layers. A view setting only: hiding a layer
    /// never changes the layout or the preset.
    public static func isDrawn(_ layer: Int?, hidden: Set<Int>) -> Bool {
        guard let layer else { return true }
        return !hidden.contains(layer)
    }

    /// The deepest layer a box can be moved to from the editor: one past the deepest in use, so a
    /// box can always be sent behind everything else.
    public static func deepestChoice(_ layers: [Int?]) -> Int {
        (layers.compactMap { $0 }.max() ?? 0) + 1
    }
}

/// The name a new layout or preset takes when nothing is typed: the next free "Layout n" / "Preset n".
public enum WindowDefaultName {
    public static func next(_ word: String, taken: [String]) -> String {
        let names = Set(taken.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        var number = 1
        while names.contains("\(word) \(number)") { number += 1 }
        return "\(word) \(number)"
    }

    /// The typed name, or the default when nothing was typed.
    public static func resolve(_ typed: String, word: String, taken: [String]) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? next(word, taken: taken) : trimmed
    }
}
