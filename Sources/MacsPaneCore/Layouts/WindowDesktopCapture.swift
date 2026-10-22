import CoreGraphics

/// What "the current desktop" means when it is drawn on the display, copied into a new layout, or
/// saved as a preset: the windows actually sitting on this screen, whatever shape they are in.
///
/// This is deliberately NOT `WindowPlacementClassifier`. That one answers "is this window tiled to a
/// layout box", which is a readback ("3 of 7 tiled"). Capturing the desktop must take the freeform
/// windows too — they are the whole reason to save an arrangement you arrived at by hand.
public enum WindowDesktopCapture {
    /// A window is captured when a real part of it is on this screen and it is big enough to be a
    /// box. Windows sharing one frame are captured once — a stack reads as a single box — and the
    /// incoming (front-to-back) order is preserved.
    public static func capturedIDs(_ frames: [(UInt32, CGRect)],
                                   minimumArea: CGFloat = 0.01,
                                   minimumOnScreen: CGFloat = 0.5) -> [UInt32] {
        var seen: Set<String> = []
        return frames.compactMap { id, frame in
            guard qualifies(frame, minimumArea: minimumArea, minimumOnScreen: minimumOnScreen),
                  seen.insert(key(for: frame)).inserted
            else { return nil }
            return id
        }
    }

    public static func qualifies(_ frame: CGRect, minimumArea: CGFloat = 0.01,
                                 minimumOnScreen: CGFloat = 0.5) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let area = frame.width * frame.height
        guard area >= minimumArea else { return false }
        let visible = frame.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !visible.isNull else { return false }
        return (visible.width * visible.height) / area >= minimumOnScreen
    }

    /// Frames as they are saved: clamped to the screen so a window hanging off an edge becomes a box
    /// that fits, and rounded so two windows a pixel apart don't save as two different shapes.
    public static func boxRect(for frame: CGRect) -> CGRect {
        let clamped = frame.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clamped.isNull else { return frame }
        func round(_ value: CGFloat) -> CGFloat { (value * 1_000).rounded() / 1_000 }
        return CGRect(x: round(clamped.minX), y: round(clamped.minY),
                      width: round(clamped.width), height: round(clamped.height))
    }

    private static func key(for frame: CGRect) -> String {
        [frame.minX, frame.minY, frame.width, frame.height]
            .map { String(Int(($0 * 200).rounded())) }.joined(separator: ":")
    }
}
