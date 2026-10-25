import CoreGraphics

/// Where windows stood just before MacsPane moved them, so Undo can put every one back: its frame
/// and its place in the stack. Pure, so it is tested without the window server.
public enum WindowUndoCapture {
    /// A window the user was dragging when the move began: its id and its frame (CG top-left) when it
    /// was grabbed, its home before the drag carried it to the notch.
    public struct DraggedHome: Equatable, Sendable {
        public let windowID: UInt32
        public let frame: CGRect

        public init(windowID: UInt32, frame: CGRect) {
            self.windowID = windowID
            self.frame = frame
        }
    }

    /// The placements that put `windows` back. Each goes to its frame in `roster`, a fresh front-to-back
    /// window-server snapshot taken just before the move (the window's own `frame` can be stale), and
    /// the dragged window goes home rather than to where the drag left it, even when the move itself
    /// left it out. They are listed front-to-back as they were stacked, so the arranger leaves the one
    /// that was in front in front; a window missing from the roster keeps its known frame at the back.
    /// Frames are flipped to the AppKit bottom-left the arranger expects.
    public static func priorPlacements(of windows: [ProcessWindowInfo],
                                       roster: [ProcessWindowInfo],
                                       dragged: DraggedHome?,
                                       primaryHeight: CGFloat) -> [WindowTilePlacement] {
        var moved = windows
        if let dragged, !moved.contains(where: { $0.id == dragged.windowID }),
           let window = roster.first(where: { $0.id == dragged.windowID }) {
            moved.append(window)
        }
        let live = Dictionary(roster.enumerated().map { ($1.id, (index: $0, frame: $1.frame)) },
                              uniquingKeysWith: { first, _ in first })
        var seen = Set<UInt32>()
        return moved
            .filter { seen.insert($0.id).inserted }
            .enumerated()
            .sorted { lhs, rhs in
                let l = live[lhs.element.id]?.index ?? Int.max
                let r = live[rhs.element.id]?.index ?? Int.max
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map { _, window in
                let home = window.id == dragged?.windowID ? dragged?.frame : nil
                let frame = home ?? live[window.id]?.frame ?? window.frame
                return WindowTilePlacement(window: window,
                                           frame: AXCoordinateConverter.flipRect(frame, primaryHeight: primaryHeight))
            }
    }
}
