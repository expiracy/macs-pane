import CoreGraphics
import Foundation

/// Turns live windows into a saved `SnapLayout` — the geometry behind "Save current windows" (both
/// the Settings entry and the notch save surface) and the save preview's tile positions. Pure so the
/// region math is unit-tested; the AppKit side supplies the screen's visible frame, the primary
/// display height (for the CG→AppKit flip), and the pid→bundle-id lookup.
public enum SnapLayoutSnapshotter {
    /// Snapshot `windows` — one region PER WINDOW at its current on-screen position, bound to its
    /// app — into a named layout, or nil if none qualify. Keeping one region per window preserves
    /// stacks and multiple windows of an app; applying fans the app's windows back across its
    /// regions (front-most on top). `launch` is the per-window "launch if closed" toggle; a window
    /// whose bundle id can't be resolved is skipped.
    public static func snapshot(of windows: [ProcessWindowInfo], named name: String,
                                visibleFrame: CGRect, primaryHeight: CGFloat,
                                bundleID: (ProcessWindowInfo) -> String?,
                                launch: (ProcessWindowInfo) -> Bool = { _ in true }) -> SnapLayout? {
        let slots: [SnapLayoutSlot] = windows.compactMap { window in
            guard let bundle = bundleID(window),
                  let unit = unitFrame(for: window, visibleFrame: visibleFrame,
                                       primaryHeight: primaryHeight) else { return nil }
            let rect = NormalizedRect(x: unit.minX, y: unit.minY, width: unit.width, height: unit.height)
            return SnapLayoutSlot(region: .custom(rect), binding: .app(bundleID: bundle),
                                  launchIfClosed: launch(window))
        }
        guard !slots.isEmpty else { return nil }
        return SnapLayout(name: name, slots: slots)
    }

    /// A window's current frame as a unit rect of `visibleFrame` (0…1, bottom-left origin), or nil
    /// when the frame is degenerate. Window frames arrive in CG top-left global coordinates (as
    /// `CGWindowListCopyWindowInfo` reports them) and are flipped to AppKit before normalising.
    public static func unitFrame(for window: ProcessWindowInfo, visibleFrame: CGRect,
                                 primaryHeight: CGFloat) -> CGRect? {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return nil }
        let appKit = AXCoordinateConverter.flipRect(window.frame, primaryHeight: primaryHeight)
        return CGRect(x: (appKit.minX - visibleFrame.minX) / visibleFrame.width,
                      y: (appKit.minY - visibleFrame.minY) / visibleFrame.height,
                      width: appKit.width / visibleFrame.width,
                      height: appKit.height / visibleFrame.height)
    }
}
