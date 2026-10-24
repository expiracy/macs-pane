import CoreGraphics

/// Keeps a box being drawn, moved or resized inside the display, and, when the grid is on, lands
/// its edges on a fine lattice so layouts line up cleanly. Unit coordinates, top-left origin (the
/// display's own drawing space).
public enum WindowDrawGrid {
    /// Fine enough for thirds, quarters, sixths, eighths and twelfths across; fifteen rows keep the
    /// cells square on a 16:10 display.
    public static let columns = 24
    public static let rows = 15

    /// A pointer position pulled back inside the display.
    public static func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }

    /// The nearest lattice line to `value` with `steps` cells across the unit.
    public static func snap(_ value: CGFloat, steps: Int) -> CGFloat {
        guard steps > 0 else { return value }
        return (value * CGFloat(steps)).rounded() / CGFloat(steps)
    }

    /// The rectangle spanned by two pointer positions, inside the display and optionally on the grid.
    /// On the grid it is at least one cell each way.
    public static func rect(from start: CGPoint, to end: CGPoint, grid: Bool) -> CGRect {
        var a = clamp(start), b = clamp(end)
        if grid {
            a = CGPoint(x: snap(a.x, steps: columns), y: snap(a.y, steps: rows))
            b = CGPoint(x: snap(b.x, steps: columns), y: snap(b.y, steps: rows))
            if a.x == b.x { b.x = a.x < 1 ? a.x + 1 / CGFloat(columns) : a.x - 1 / CGFloat(columns) }
            if a.y == b.y { b.y = a.y < 1 ? a.y + 1 / CGFloat(rows) : a.y - 1 / CGFloat(rows) }
        }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// A box moved by the pointer: kept whole and inside the display, its origin on the grid if on.
    public static func moved(_ rect: CGRect, by delta: CGSize, grid: Bool) -> CGRect {
        var x = rect.minX + delta.width, y = rect.minY + delta.height
        if grid { x = snap(x, steps: columns); y = snap(y, steps: rows) }
        x = min(max(x, 0), max(0, 1 - rect.width))
        y = min(max(y, 0), max(0, 1 - rect.height))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// Which edges of a box a drag grabs, one side, or two at a corner.
    public struct Edges: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let left = Edges(rawValue: 1)
        public static let right = Edges(rawValue: 2)
        public static let top = Edges(rawValue: 4)
        public static let bottom = Edges(rawValue: 8)
    }

    /// The edges within `tolerance` of `point`, for a box drawn at `rect` (both in the same space,
    /// top-left origin). Empty in the box's middle, that grabs the whole box to move it.
    public static func edges(at point: CGPoint, in rect: CGRect, tolerance: CGFloat) -> Edges {
        guard rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return [] }
        let band = min(tolerance, rect.width / 3, rect.height / 3)
        var edges: Edges = []
        if point.x <= rect.minX + band { edges.insert(.left) } else if point.x >= rect.maxX - band { edges.insert(.right) }
        if point.y <= rect.minY + band { edges.insert(.top) } else if point.y >= rect.maxY - band { edges.insert(.bottom) }
        return edges
    }

    /// A box resized from its bottom-right corner.
    public static func resized(_ rect: CGRect, by delta: CGSize, grid: Bool, minimum: CGFloat = 0.03) -> CGRect {
        resized(rect, edges: [.right, .bottom], by: delta, grid: grid, minimum: minimum)
    }

    /// A box resized by dragging `edges`: the other edges stay put, it never passes the display's
    /// edge, and it is never smaller than `minimum` (or one cell on the grid).
    public static func resized(_ rect: CGRect, edges: Edges, by delta: CGSize, grid: Bool,
                               minimum: CGFloat = 0.03) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        var minWidth = minimum, minHeight = minimum
        if grid { minWidth = max(minimum, 1 / CGFloat(columns)); minHeight = max(minimum, 1 / CGFloat(rows)) }
        func onGrid(_ value: CGFloat, _ steps: Int) -> CGFloat { grid ? snap(value, steps: steps) : value }
        if edges.contains(.left) { minX = max(onGrid(minX + delta.width, columns), 0) }
        if edges.contains(.right) { maxX = min(onGrid(maxX + delta.width, columns), 1) }
        if edges.contains(.top) { minY = max(onGrid(minY + delta.height, rows), 0) }
        if edges.contains(.bottom) { maxY = min(onGrid(maxY + delta.height, rows), 1) }
        let width = max(maxX - minX, minWidth), height = max(maxY - minY, minHeight)
        return CGRect(x: edges.contains(.left) ? maxX - width : minX,
                      y: edges.contains(.top) ? maxY - height : minY, width: width, height: height)
    }
}
