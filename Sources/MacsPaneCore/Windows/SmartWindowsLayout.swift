import CoreGraphics

/// Maps a window count to a clean, count-appropriate tiling, the "smart by count" layout the notch's
/// Smart Windows action arranges your most-recently-used windows into. Slot order **is** MRU order: the
/// most recent window takes the first slot, the next the second, and so on.
///
/// Small counts use curated zones (`WindowSnapZone`, the same tested frame math and AppKit bottom-left
/// convention as Window Snap); five or more windows fall back to an even grid (`gridFrames`). There is
/// **no upper bound**, the picker offers every recent window and the grid densifies as the count grows.
public enum SmartWindowsLayout {
    /// The curated zones for a small `count`, in slot (= MRU) order:
    ///  - 1 → one maximized window
    ///  - 2 → side-by-side halves
    ///  - 3 → one big left half + two stacked quarters on the right
    ///  - 4 → four quarters, in reading order (top-left, top-right, bottom-left, bottom-right)
    ///
    /// Only meaningful for `1...4`, `frames(for:in:)` routes five-plus through `gridFrames`. A count at
    /// or below zero clamps to a single maximized window, keeping the function total.
    public static func zones(for count: Int) -> [WindowSnapZone] {
        switch max(1, count) {
        case 1: return [.maximize]
        case 2: return [.leftHalf, .rightHalf]
        case 3: return [.leftHalf, .topRightQuarter, .bottomRightQuarter]
        default: return [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
        }
    }

    /// The target frames for `count` windows within a screen's visible frame (AppKit bottom-left), in
    /// slot order: `1...4` resolve the curated `zones(for:)`, five-plus tile an even `gridFrames`.
    public static func frames(for count: Int, in visibleFrame: CGRect) -> [CGRect] {
        let n = max(1, count)
        return n <= 4
            ? zones(for: n).map { $0.frame(in: visibleFrame) }
            : gridFrames(count: n, in: visibleFrame)
    }

    /// Pair each selected window (already in MRU/slot order) with its target frame, exactly what the
    /// picker hands the arranger. Every window gets a frame (the layout grows to fit the selection), so
    /// the slot count always matches the window count.
    public static func placements(for windows: [ProcessWindowInfo],
                                  in visibleFrame: CGRect) -> [WindowTilePlacement] {
        zip(windows, frames(for: windows.count, in: visibleFrame))
            .map { WindowTilePlacement(window: $0, frame: $1) }
    }

    /// An even grid for five-plus windows: `ceil(√n)` columns by `ceil(n / columns)` rows, filled
    /// row-major in slot order from the top-left. The last row may be short, its cells divide that
    /// row's width equally (stretching to fill it), so the grid always covers the visible frame with no
    /// gaps or overlap. Row 0 is the top row: in AppKit bottom-left space it sits at the highest Y.
    static func gridFrames(count n: Int, in v: CGRect) -> [CGRect] {
        let cols = Int(ceil(Double(n).squareRoot()))
        let rows = Int(ceil(Double(n) / Double(cols)))
        let rowHeight = v.height / CGFloat(rows)
        var frames: [CGRect] = []
        frames.reserveCapacity(n)
        var placed = 0
        for row in 0..<rows {
            let colsInRow = min(cols, n - placed)
            let colWidth = v.width / CGFloat(colsInRow)
            let y = v.maxY - CGFloat(row + 1) * rowHeight
            for col in 0..<colsInRow {
                frames.append(CGRect(x: v.minX + CGFloat(col) * colWidth, y: y,
                                     width: colWidth, height: rowHeight))
                placed += 1
            }
        }
        return frames
    }
}
