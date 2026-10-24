#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// The pairing-suggestion data-prep for a window drag, extracted from `WindowSnapController` so the
/// controller holds drag tracking and this holds the roster → `DragPairingSuggester` → display
/// resolution pipeline. Dependency-explicit statics: the controller hands in the roster / frames it
/// owns, so nothing here touches AX or the recency store directly.
enum WindowSnapSuggestions {
    /// Build the recent-app pairing tiles for a window drag: locate the dragged window in the recency
    /// roster and hand both to `DragPairingSuggester`, resolving each pairing's app icons + label
    /// here, once, at drag start, off the SwiftUI render path.
    static func build(for grabbed: GrabbedWindow,
                      roster: [ProcessWindowInfo],
                      grabbedFrame: CGRect?,
                      visibleFrame: CGRect) -> [ResolvedDragSuggestion] {
        guard let dragged = draggedWindow(grabbed, in: roster, grabbedFrame: grabbedFrame) else { return [] }
        return DragPairingSuggester.suggestions(dragged: dragged, recents: roster, visibleFrame: visibleFrame)
            .map(resolve)
    }

    /// Identify the dragged window in the recency roster: the entry for the grabbed pid whose frame is
    /// closest to the grabbed window's current AX frame (apps can have several windows). Falls back to the
    /// pid's most-recent window when the frame can't be read.
    private static func draggedWindow(_ grabbed: GrabbedWindow,
                                      in roster: [ProcessWindowInfo],
                                      grabbedFrame: CGRect?) -> ProcessWindowInfo? {
        let sameApp = roster.filter { $0.ownerPid == grabbed.pid }
        guard !sameApp.isEmpty else { return nil }
        guard let frame = grabbedFrame else { return sameApp.first }
        return sameApp.min(by: {
            $0.frame.origin.distance(to: frame.origin) < $1.frame.origin.distance(to: frame.origin)
        })
    }

    /// Each placement's window at its pre-tiling frame, for the Undo replay. Slot 0 is the dragged window:
    /// use its captured `draggedHome` (its position when grabbed) rather than a live frame, which by release
    /// has it mid-drag at the notch. Partners haven't moved, so a fresh snapshot is their home. CGWindowList /
    /// AX frames are top-left global; flip to the AppKit bottom-left the arranger expects.
    static func priorPlacements(_ placements: [WindowTilePlacement],
                                draggedHome: CGRect?,
                                currentFrames: [ProcessWindowInfo.ID: CGRect]) -> [WindowTilePlacement] {
        let primaryHeight = WindowControlService.primaryHeight
        return placements.enumerated().map { index, placement in
            let cgFrame = (index == 0 ? draggedHome : nil)
                ?? currentFrames[placement.window.id] ?? placement.window.frame
            return WindowTilePlacement(window: placement.window,
                                       frame: AXCoordinateConverter.flipRect(cgFrame, primaryHeight: primaryHeight))
        }
    }

    /// Resolve a Core pairing for display: per-slot app icons + a "Mail + Safari" label, from the live
    /// running apps (cached icons, cheap, and done here at drag start, not in a SwiftUI body).
    private static func resolve(_ pairing: DragPairing) -> ResolvedDragSuggestion {
        let apps = pairing.placements.map { NSRunningApplication(processIdentifier: $0.window.ownerPid) }
        return ResolvedDragSuggestion(pairing: pairing,
                                      icons: apps.map { $0?.icon },
                                      label: apps.map { $0?.localizedName ?? "Window" }.joined(separator: " + "))
    }
}
#endif
