#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// Live hover state for the collapsed drag strip, kept apart from the notch's own model so a drag
/// sweeping across it re-renders only the strip. Written by `WindowSnapController`; cleared whenever
/// the drag ends or leaves.
final class NotchDragStripModel: ObservableObject {
    /// A window drag is on the strip (inside the snap hot zone) — resting there opens the layouts.
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

/// What the widened notch shows while a window is dragged toward the top of the screen: the app's name
/// on the left of the camera and one bounded region on the right that says what resting there does, lit
/// while the drag is on it. A release on the strip itself tiles nothing — resting opens the layouts,
/// where the drop happens — so the region says that.
///
/// Laid out as two equal wings around a reserved camera gap, inset from the notch's corner curve, so the
/// lens stays centred and nothing sits under the camera.
struct NotchDragTargetStrip: View {
    @ObservedObject var strip: NotchDragStripModel
    /// Physical notch width — the centred gap the wings flank.
    let notchWidth: CGFloat
    /// The edge inset (top corner radius + `m.lg`).
    let horizontalInset: CGFloat
    @Environment(\.notchMetrics) private var m

    var body: some View {
        GeometryReader { geo in
            let wing = max(0, (geo.size.width - notchWidth) / 2 - horizontalInset)
            HStack(spacing: 0) {
                leading.frame(width: wing)
                Color.clear.frame(width: notchWidth)   // the camera lens
                trailing.frame(width: wing)
            }
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, m.xs)
        }
    }

    private var leading: some View {
        HStack(spacing: m.xs) {
            Image(systemName: "rectangle.3.group")
            Text("Windows").lineLimit(1)
            Spacer(minLength: 0)
        }
        .minimumScaleFactor(NotchDropRegion.minimumTextScale)   // notch-bound, as the region is
        .notchText(.label, weight: .semibold)
        .foregroundStyle(NotchPalette.fgSecondary)
    }

    private var trailing: some View {
        NotchDropRegion(systemImage: "rectangle.split.2x1", title: "Hold for layouts", lit: strip.windowOnTarget)
    }
}
#endif
