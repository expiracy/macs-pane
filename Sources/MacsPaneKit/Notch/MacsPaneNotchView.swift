#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// What MacsPane draws at the top of the screen: the notch's black silhouette at the host's
/// `shapeSize`, holding the drag-target strip while a window is dragged and the snap picker once the
/// drag rests. Display-only: the panel ignores the mouse, and the drag is read by global monitors.
struct MacsPaneNotchView: View {
    @ObservedObject var host: MacsPaneSnapHost
    @Environment(\.notchMetrics) private var m

    private var open: Bool { host.stage == .picker }
    private var topRadius: CGFloat {
        host.hasRealNotch ? (open ? m.rootTopRadiusExpanded : m.rootTopRadiusCompact) : 0
    }
    private var bottomRadius: CGFloat { open ? m.rootBottomRadiusExpanded : m.rootBottomRadiusCompact }
    /// The picker's pairing wing hangs off the left; shifting the shape by half of it keeps the layout
    /// tiles centred on the camera.
    private var wing: CGFloat { open ? host.snapWingWidth : 0 }

    var body: some View {
        let size = host.shapeSize
        let silhouette = NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
        ZStack(alignment: .top) {
            switch host.stage {
            case .rest:
                EmptyView()
            case .target:
                NotchDragTargetStrip(strip: host.dragStrip, notchWidth: host.notchSize.width,
                                     horizontalInset: topRadius + m.lg)
                    .transition(.opacity)
            case .picker:
                WindowSnapView(model: host.windowSnap, tileScale: host.rowScale)
                    .padding(.top, host.notchSize.height + m.sm)
                    .padding(.horizontal, WindowSnapPickerLayout.rowPadding / 2)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(silhouette.fill(NotchPalette.surfaceBase))
        .clipShape(silhouette)
        .shadow(color: open ? NotchPalette.panelShadow : Color.clear,
                radius: NotchPalette.panelShadowRadius, y: NotchPalette.panelShadowY)
        .padding(.trailing, wing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The tiles report their frames in this space; the snap controller maps the drag pointer into it.
        .coordinateSpace(name: WindowSnapView.panelSpace)
        .onPreferenceChange(SnapFamilyFramesKey.self) { host.windowSnap.setFamilyFrames($0) }
        .onPreferenceChange(SnapSuggestionFramesKey.self) { host.windowSnap.setSuggestionFrames($0) }
        .allowsHitTesting(false)
    }
}
#endif
