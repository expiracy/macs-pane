import CoreGraphics

/// The desktop as it sits, turned into a layout's boxes or a preset — "From current windows" and
/// "Save as preset" on the Windows page, and the same two commands in MacsPane's menu. Composes the
/// capture rule (`WindowDesktopCapture`), the frame maths (`SnapLayoutSnapshotter`) and the layer rule
/// (`WindowBoxLayers`) once, so both apps capture exactly the same windows the same way.
public enum WindowDesktopSnapshot {
    /// The windows the capture keeps, in the incoming (front-to-back) order.
    public static func captured(_ windows: [ProcessWindowInfo], visibleFrame: CGRect,
                                primaryHeight: CGFloat) -> [ProcessWindowInfo] {
        let frames = windows.compactMap { window -> (UInt32, CGRect)? in
            guard let unit = SnapLayoutSnapshotter.unitFrame(for: window, visibleFrame: visibleFrame,
                                                             primaryHeight: primaryHeight) else { return nil }
            return (window.id, unit)
        }
        let ids = Set(WindowDesktopCapture.capturedIDs(frames))
        return windows.filter { ids.contains($0.id) }
    }

    /// One box per captured window, at the frame it occupies, clamped and rounded as saved.
    public static func boxes(of windows: [ProcessWindowInfo], visibleFrame: CGRect,
                             primaryHeight: CGFloat) -> [SnapRegion] {
        captured(windows, visibleFrame: visibleFrame, primaryHeight: primaryHeight).compactMap { window in
            SnapLayoutSnapshotter.unitFrame(for: window, visibleFrame: visibleFrame, primaryHeight: primaryHeight)
        }
        .map { custom(WindowDesktopCapture.boxRect(for: $0)) }
    }

    /// The captured windows as an unsaved preset: each box bound to its window's app, layered by where
    /// it sits. Nil when nothing qualifies or no window's app can be named.
    public static func preset(of windows: [ProcessWindowInfo], named name: String,
                              visibleFrame: CGRect, primaryHeight: CGFloat,
                              bundleID: (ProcessWindowInfo) -> String?) -> SnapLayout? {
        let kept = captured(windows, visibleFrame: visibleFrame, primaryHeight: primaryHeight)
        guard var snapshot = SnapLayoutSnapshotter.snapshot(of: kept, named: name, visibleFrame: visibleFrame,
                                                            primaryHeight: primaryHeight, bundleID: bundleID)
        else { return nil }
        for index in snapshot.slots.indices {
            snapshot.slots[index].region = custom(WindowDesktopCapture.boxRect(for: snapshot.slots[index].region.unitRect))
        }
        let layers = WindowBoxLayers.resolve(snapshot.slots.map(\.region.unitRect))
        for index in snapshot.slots.indices { snapshot.slots[index].layer = layers[index] }
        return snapshot
    }

    private static func custom(_ rect: CGRect) -> SnapRegion {
        .custom(NormalizedRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
    }
}
