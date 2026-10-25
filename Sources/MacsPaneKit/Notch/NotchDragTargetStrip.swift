#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// Live hover state for the collapsed drag strip, kept apart from the notch's own model so a drag
/// sweeping across it re-renders only the strip. Written by `WindowSnapController`; cleared whenever
/// the drag ends or leaves.
final class NotchDragStripModel: ObservableObject {
    /// A window drag is on the strip (inside the snap hot zone), resting there opens the layouts.
    @Published var windowOnTarget = false

    /// Called on every window-drag event; publishes only on a change so the strip isn't re-rendered per
    /// mouse move. `WindowSnapController` passes "inside the hot zone while collapsed".
    func setWindowOnTarget(_ onTarget: Bool) {
        if windowOnTarget != onTarget { windowOnTarget = onTarget }
    }

    func reset() {
        if windowOnTarget { windowOnTarget = false }
    }
}
#endif
