import CoreGraphics

/// One window to be moved to one target frame, a single Smart Windows placement. The order of a
/// placement list is slot order, which is MRU order (the most recent window first).
public struct WindowTilePlacement: Equatable, Sendable {
    public let window: ProcessWindowInfo
    /// Target frame in AppKit bottom-left coordinates (a `SmartWindowsLayout` frame within a visible frame).
    public let frame: CGRect

    public init(window: ProcessWindowInfo, frame: CGRect) {
        self.window = window
        self.frame = frame
    }
}

/// The port Smart Windows moves windows through, one call places every selected window. A protocol so
/// the use-case stays testable off the window server: the live adapter (`AXWindowArranger`) drives
/// Accessibility, a fake records the placements it was asked to make (the `SymbolicHotKeyBackend` ←
/// live-adapter + mock pattern).
public protocol WindowArranging {
    /// Place each window at its frame. `completion` is called on the main thread with how many of the
    /// placements actually landed (AX moves can silently fail / be clamped).
    func arrange(_ placements: [WindowTilePlacement], completion: ((Int) -> Void)?)
}
