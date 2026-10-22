import CoreGraphics

/// Pure notch geometry. Built from plain screen values (not a live `NSScreen`) so it is
/// unit-testable and can live in Core. All rects use AppKit's bottom-left origin convention,
/// matching `NSScreen.frame` and `NSEvent.mouseLocation`.
public struct NotchGeometry: Equatable, Sendable {
    /// Full frame of the screen the notch lives on.
    public let screenFrame: CGRect
    /// The collapsed strip that overlays the physical notch (or a sensible fallback size).
    public let collapsedSize: CGSize
    /// Height of the menu bar on this screen.
    public let menubarHeight: CGFloat
    /// Whether this screen actually has a camera notch.
    public let hasRealNotch: Bool

    /// A standard MacBook camera-notch footprint. Used as the hover-trigger size on a screen with no
    /// real notch when no notched display exists in the system to mirror (a pure desktop Mac, or a
    /// notch MacBook running clamshell). Roughly a 14"/16" MacBook Pro notch.
    public static let standardNotchSize = CGSize(width: 200, height: 32)

    public init(screenFrame: CGRect,
                safeAreaTop: CGFloat,
                leftAuxWidth: CGFloat?,
                rightAuxWidth: CGFloat?,
                menubarHeight: CGFloat,
                fallbackNotchSize: CGSize = NotchGeometry.standardNotchSize) {
        self.screenFrame = screenFrame
        self.menubarHeight = menubarHeight
        if let left = leftAuxWidth, let right = rightAuxWidth, safeAreaTop > 0 {
            self.hasRealNotch = true
            self.collapsedSize = CGSize(width: max(0, screenFrame.width - left - right),
                                        height: safeAreaTop)
        } else {
            self.hasRealNotch = false
            // No physical notch (external monitor / non-notch Mac): mirror a real notch's footprint,
            // top-centred, so the hover trigger stays the same as on a notched MacBook. Height is at
            // least the menu bar so the zone is never thinner than the bar it sits under.
            self.collapsedSize = CGSize(width: fallbackNotchSize.width,
                                        height: max(menubarHeight, fallbackNotchSize.height))
        }
    }

    /// The collapsed strip rect, centered at the top of the screen — also the pointer hot-zone
    /// that triggers expansion.
    public var collapsedRect: CGRect {
        CGRect(x: screenFrame.midX - collapsedSize.width / 2,
               y: screenFrame.maxY - collapsedSize.height,
               width: collapsedSize.width,
               height: collapsedSize.height)
    }

    /// The panel window: sized to comfortably contain the expanded notch (plus margin for the
    /// open animation's overshoot and the drop shadow), pinned to the top-center of the screen.
    /// Kept modest — not full-screen — so only the notch itself is on screen; the surrounding
    /// transparent margin is small. The notch content sits flush with the window's top edge.
    public func windowFrame(contentSize: CGSize, horizontalMargin: CGFloat = 160, bottomMargin: CGFloat = 120) -> CGRect {
        let width = contentSize.width + horizontalMargin
        let height = contentSize.height + bottomMargin
        return CGRect(x: screenFrame.midX - width / 2,
                      y: screenFrame.maxY - height,
                      width: width,
                      height: height)
    }

    /// The on-screen rect the expanded notch occupies (top-center), for pointer hit-testing.
    public func expandedRect(size: CGSize) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2,
               y: screenFrame.maxY - size.height,
               width: size.width,
               height: size.height)
    }

    /// The "drag toward the notch opens it" zone: the collapsed strip enlarged by `inset` (top-center,
    /// extending downward). At `inset == .zero` this is exactly `collapsedRect` — i.e. "right on the
    /// notch". Used by `windowSnapZone` to build the centred window-drag target.
    public func approachRect(inset: CGSize) -> CGRect {
        let width = collapsedSize.width + inset.width
        let height = collapsedSize.height + inset.height
        return CGRect(x: screenFrame.midX - width / 2,
                      y: screenFrame.maxY - height,
                      width: width,
                      height: height)
    }

    /// The collapsed window-snap trigger: the notch widened to `targetWidth`, centred at the top, only
    /// as tall as the notch itself — so the cursor must be ON the notch, not under the menu bar below
    /// it. Sized to match the rendered widened notch ("what you see is what you hit"). Centred (not
    /// full-width) so a window dragged up elsewhere along the menu bar is left alone.
    public func windowSnapCollapsedZone(targetWidth: CGFloat) -> CGRect {
        CGRect(x: screenFrame.midX - targetWidth / 2,
               y: screenFrame.maxY - collapsedSize.height,
               width: targetWidth,
               height: collapsedSize.height)
    }

    /// The expanded window-snap zone: the open picker footprint plus `slack` on every side, so the
    /// pointer can travel onto the outermost tiles without falling out and collapsing it.
    /// `leftExtension` is the pairing wing annexed to the picker's LEFT: `size` already includes its
    /// width, but the shape shifts left by half of it so the family tiles stay centred on the notch —
    /// the zone shifts the same way so it covers exactly the rendered shape (what you see is what you hit).
    public func windowSnapExpandedZone(size: CGSize, leftExtension: CGFloat = 0, slack: CGFloat) -> CGRect {
        expandedRect(size: size)
            .offsetBy(dx: -leftExtension / 2, dy: 0)
            .insetBy(dx: -slack, dy: -slack)
    }

    /// The collapsed notch widened into a window-drag target: a fraction of the screen width, floored
    /// at the notch's own width so it's never narrower than the strip. The single source the view
    /// model (rendered width) and the controller (hit-zone width) both derive from, so they agree.
    public static func dragTargetWidth(screenWidth: CGFloat, notchWidth: CGFloat, fraction: CGFloat) -> CGFloat {
        max(screenWidth * fraction, notchWidth)
    }
}
