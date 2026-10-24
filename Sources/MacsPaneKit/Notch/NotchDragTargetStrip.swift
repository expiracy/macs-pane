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

/// What the widened notch shows while a window is dragged toward the top of the screen: the Layouts
/// title, the same one the open notch shows, beside the camera, brightening while the drag is on it.
/// Resting there opens the picker. The strip is as wide as the open notch, so opening only grows it down.
struct NotchDragTargetStrip: View {
    @ObservedObject var strip: NotchDragStripModel
    /// The shape's top corner radius: the title sits just in from it.
    let topRadius: CGFloat

    var body: some View {
        SnapHeading.layouts
            .opacity(strip.windowOnTarget ? 1 : 0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, SnapHeading.inset(fromCorner: topRadius))
            .animation(NotchMotion.fast, value: strip.windowOnTarget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Layouts. Hold here to open them.")
    }
}
#endif
