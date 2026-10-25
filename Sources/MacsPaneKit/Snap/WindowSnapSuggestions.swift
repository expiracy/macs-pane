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
    static func draggedWindow(_ grabbed: GrabbedWindow,
                                      in roster: [ProcessWindowInfo],
                                      grabbedFrame: CGRect?) -> ProcessWindowInfo? {
        let sameApp = roster.filter { $0.ownerPid == grabbed.pid }
        guard !sameApp.isEmpty else { return nil }
        guard let frame = grabbedFrame else { return sameApp.first }
        return sameApp.min(by: {
            $0.frame.origin.distance(to: frame.origin) < $1.frame.origin.distance(to: frame.origin)
        })
    }

    /// The dragged window's home for an Undo: which roster window it is (the window server's own id
    /// when the bridge reads it, else the grabbed app's window nearest its frame now) and `home`, where
    /// it was grabbed, rather than wherever the drag has carried it by the release.
    static func draggedHome(_ grabbed: GrabbedWindow, home: CGRect?, currentFrame: CGRect?,
                            roster: [ProcessWindowInfo]) -> WindowUndoCapture.DraggedHome? {
        guard let home else { return nil }
        let id = AXWindowBridge.windowID(of: grabbed.element)
            ?? draggedWindow(grabbed, in: roster, grabbedFrame: currentFrame)?.id
        return id.map { WindowUndoCapture.DraggedHome(windowID: $0, frame: home) }
    }

    /// Resolve a Core pairing for display: per-slot app icons + a "Mail + Safari" label, from the live
    /// running apps (cached icons, cheap, and done here at drag start, not in a SwiftUI body).
    private static func resolve(_ pairing: DragPairing) -> ResolvedDragSuggestion {
        let apps = pairing.placements.map { NSRunningApplication(processIdentifier: $0.window.ownerPid) }
        return ResolvedDragSuggestion(pairing: pairing,
                                      icons: apps.map { app in app?.bundleURL.map(SnapAppIcons.icon(forAppAt:)) ?? app?.icon },
                                      label: apps.map { $0?.localizedName ?? "Window" }.joined(separator: " + "))
    }
}
#endif
