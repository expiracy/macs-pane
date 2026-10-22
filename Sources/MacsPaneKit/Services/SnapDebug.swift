#if canImport(AppKit)
import AppKit
import CoreGraphics

/// Opt-in tracing for the window-snap hot path, gated by the `MACSPANE_SNAP_DEBUG` environment variable.
/// Both the drag state machine (`WindowSnapController`) and the AX window classifier
/// (`WindowControlService`) log through here, so the gate and the coordinate formatters live in one
/// place instead of drifting between two copies. Off by default; messages are built lazily
/// (`@autoclosure`), so there is no cost when the variable is unset.
///
/// Set `MACSPANE_SNAP_DEBUG=1` to trace why a given drag didn't open the notch (didn't classify as a
/// window? didn't reach the zone? where was the pointer?) — output goes to the unified log
/// (Console.app, or the terminal if launched from one).
enum SnapDebug {
    static let enabled = ProcessInfo.processInfo.environment["MACSPANE_SNAP_DEBUG"] != nil

    static func log(_ message: @autoclosure () -> String) {
        if enabled { NSLog("[WindowSnap] %@", message()) }
    }

    static func fmt(_ p: CGPoint) -> String { String(format: "(%.0f,%.0f)", p.x, p.y) }
    static func fmt(_ r: CGRect) -> String { String(format: "[x %.0f–%.0f y %.0f–%.0f]", r.minX, r.maxX, r.minY, r.maxY) }
    static func fmt(_ s: CGSize) -> String { String(format: "%.0f×%.0f", s.width, s.height) }
}
#endif
