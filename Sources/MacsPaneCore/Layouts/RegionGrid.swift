/// A cols×rows lattice the custom-region editor snaps to. A region is a rectangular block of cells
/// (a drag from one cell to another); this turns that block into a `NormalizedRect`. Cells are
/// addressed 0-based from the TOP-LEFT (how the grid reads on screen); the emitted rect is bottom-left
/// to match `WindowSnapZone` / `NormalizedRect`. Pure value math so the editor stays unit-testable.
public struct RegionGrid: Equatable, Sendable {
    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = min(max(cols, 1), 12)
        self.rows = min(max(rows, 1), 12)
    }

    /// A single cell address, 0-based from the top-left.
    public struct Cell: Equatable, Sendable {
        public var col: Int
        public var row: Int
        public init(col: Int, row: Int) { self.col = col; self.row = row }
    }

    /// The normalized rect spanning the inclusive cell block between two cells (order-independent).
    public func rect(from a: Cell, to b: Cell) -> NormalizedRect {
        let c0 = clamp(min(a.col, b.col), 0, cols - 1)
        let c1 = clamp(max(a.col, b.col), 0, cols - 1)
        let r0 = clamp(min(a.row, b.row), 0, rows - 1)
        let r1 = clamp(max(a.row, b.row), 0, rows - 1)
        let x = Double(c0) / Double(cols)
        let w = Double(c1 - c0 + 1) / Double(cols)
        let h = Double(r1 - r0 + 1) / Double(rows)
        let y = 1.0 - Double(r1 + 1) / Double(rows)   // flip top-left rows down to a bottom-left origin
        return NormalizedRect(x: x, y: y, width: w, height: h)
    }

    private func clamp(_ value: Int, _ lo: Int, _ hi: Int) -> Int { min(max(value, lo), hi) }
}
