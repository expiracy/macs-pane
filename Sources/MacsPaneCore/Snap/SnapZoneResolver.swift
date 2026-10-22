import CoreGraphics

/// Maps a pointer location to a snap zone by screen-edge proximity — the Magnet/Rectangle "drag to
/// an edge" model. In the notch the *picker tiles* are the primary selector (the user drags onto a
/// region tile), so this resolver is the documented fallback / future path for snapping without the
/// notch. Pure and unit-testable: it takes a pointer and a `visibleFrame` (both AppKit bottom-left)
/// and returns a zone, or `nil` for the large central dead zone where no snap is intended.
public enum SnapZoneResolver {
    /// - Parameters:
    ///   - p: pointer location, AppKit bottom-left coords.
    ///   - v: the screen's visible frame, AppKit bottom-left.
    ///   - edgeFraction: how close to a left/right edge counts as a half (fraction of width).
    ///   - cornerFraction: how close to the top/bottom counts as a corner when also near a side.
    ///   - topMaximizeFraction: a band along the very top (the notch neighbourhood) → maximize.
    public static func zone(pointer p: CGPoint,
                            visibleFrame v: CGRect,
                            edgeFraction: CGFloat = 0.06,
                            cornerFraction: CGFloat = 0.20,
                            topMaximizeFraction: CGFloat = 0.10) -> WindowSnapZone? {
        guard v.contains(p), v.width > 0, v.height > 0 else { return nil }
        let nx = (p.x - v.minX) / v.width            // 0 (left) … 1 (right)
        let nyFromTop = (v.maxY - p.y) / v.height     // 0 (top) … 1 (bottom), AppKit Y flipped

        let nearLeft = nx <= edgeFraction
        let nearRight = nx >= 1 - edgeFraction
        let nearTop = nyFromTop <= cornerFraction
        let nearBottom = nyFromTop >= 1 - cornerFraction

        // Corners win when the pointer hugs a side *and* the top or bottom.
        if nearLeft && nearTop { return .topLeftQuarter }
        if nearRight && nearTop { return .topRightQuarter }
        if nearLeft && nearBottom { return .bottomLeftQuarter }
        if nearRight && nearBottom { return .bottomRightQuarter }

        // Dragging up toward the notch (the top band) maximizes.
        if nyFromTop <= topMaximizeFraction { return .maximize }
        if nearLeft { return .leftHalf }
        if nearRight { return .rightHalf }
        return nil
    }
}
