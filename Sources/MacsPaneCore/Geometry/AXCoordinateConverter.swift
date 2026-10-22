import CoreGraphics

/// Pure conversion between AppKit's screen coordinates (bottom-left origin, Y up — used by
/// `NSScreen.frame` and `NSEvent.mouseLocation`) and the Accessibility API's global coordinates
/// (top-left origin, Y down — used by `kAXPositionAttribute`). Both spaces share the same X axis
/// and the same global origin column; they differ only by a flip of Y about the **primary** screen.
///
/// The single screen fact this needs is the primary (menu-bar) screen's height —
/// `CGDisplayBounds(CGMainDisplayID()).height` — so the math is testable with no live `NSScreen`,
/// the same discipline as `NotchGeometry`. The formula holds for any multi-monitor arrangement,
/// including displays stacked above the primary (which have AppKit Y greater than the primary
/// height and therefore a *negative* AX Y — correctly above the global top-left origin).
public enum AXCoordinateConverter {
    /// AppKit point (bottom-left) → Accessibility global point (top-left). Involutive: applying it
    /// twice returns the original, so the same function converts both directions.
    public static func flipPoint(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// AppKit rect (bottom-left) → Accessibility global rect (top-left). The AX origin is the rect's
    /// top-left corner, which in AppKit is `(minX, maxY)`; size is unchanged.
    public static func flipRect(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
