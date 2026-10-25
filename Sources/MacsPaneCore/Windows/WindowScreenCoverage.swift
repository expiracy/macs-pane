import CoreGraphics

/// Whether a window's frame actually lands on a display, the roster filter that drops "parked"
/// ghost windows (helpers stashed at extreme off-screen coordinates that the window server still
/// reports as on-screen). Pure geometry: the AppKit layer hands it the display frames in the same
/// CG top-left-global space `CGWindowListCopyWindowInfo` reports window bounds in.
public enum WindowScreenCoverage {
    /// The minimum overlap in each dimension for a window to count as "on" a display. Small on
    /// purpose: a real window dragged nearly off the edge should stay eligible (tiling it brings
    /// it back); only fully-parked ghosts and sub-shadow slivers fall below it.
    public static let minSpan: CGFloat = 8

    /// True when `frame` overlaps at least one display by `minSpan` points in both dimensions.
    public static func intersectsAnyDisplay(_ frame: CGRect, displays: [CGRect],
                                            minSpan: CGFloat = WindowScreenCoverage.minSpan) -> Bool {
        displays.contains { display in
            let overlap = display.intersection(frame)
            return overlap.width >= minSpan && overlap.height >= minSpan
        }
    }

    /// The index of the display that holds the most of `frame`, the screen a window is on; nil when
    /// it is on none. Both in the same space.
    public static func displayHoldingMost(of frame: CGRect, displays: [CGRect]) -> Int? {
        let areas = displays.map { display -> CGFloat in
            let overlap = display.intersection(frame)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }
}
