#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// What MacsPane draws at the top of the screen: the notch's black silhouette at the host's
/// `shapeSize`, holding the drag-target strip while a window is dragged and the snap picker once the
/// drag rests, with the picker's islands floating either side (pairings left, your presets right).
/// Display-only: the panel ignores the mouse, and the drag is read by global monitors.
struct MacsPaneNotchView: View {
    @ObservedObject var host: MacsPaneSnapHost
    @Environment(\.notchMetrics) private var m

    private var open: Bool { host.stage == .picker }
    private var topRadius: CGFloat {
        host.hasRealNotch ? (open ? m.rootTopRadiusExpanded : m.rootTopRadiusCompact) : 0
    }
    private var bottomRadius: CGFloat { open ? m.rootBottomRadiusExpanded : m.rootBottomRadiusCompact }

    var body: some View {
        let layout = host.layout()
        let side = open ? max(layout.leftIslandSize.width, layout.rightIslandSize.width) : 0
        // Each island gets a slot as wide as the wider one, so the notch stays centred on the camera. The
        // gap is measured from the notch's body: its flared top corners sit above the islands.
        HStack(alignment: .top, spacing: side > 0 ? WindowSnapMetrics.islandGap - topRadius : 0) {
            if side > 0 {
                island(.suggestions, shown: !host.windowSnap.suggestions.isEmpty, alignment: .trailing, width: side)
            }
            notch
            if side > 0 {
                island(.presets, shown: !host.windowSnap.presets.isEmpty, alignment: .leading, width: side)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The tiles report their frames in this space; the snap controller maps the drag pointer into it.
        .coordinateSpace(name: WindowSnapView.panelSpace)
        .onPreferenceChange(SnapFamilyFramesKey.self) { host.windowSnap.setFamilyFrames($0) }
        .onPreferenceChange(SnapSuggestionFramesKey.self) { host.windowSnap.setSuggestionFrames($0) }
        .onPreferenceChange(SnapPresetFramesKey.self) { host.windowSnap.setPresetFrames($0) }
        .allowsHitTesting(false)
    }

    /// An island buds off the notch's side a beat after the notch starts to open: small, blurred and
    /// tucked against the notch, it springs out to its place with a little overshoot (the left one first),
    /// and its tiles pop in after it. Closing, it shrinks back into the notch.
    private func island(_ kind: WindowSnapIsland.Kind, shown: Bool, alignment: Alignment, width: CGFloat) -> some View {
        let left = kind == .suggestions
        let bud = IslandBud(towardNotch: left ? 70 : -70, anchor: left ? .trailing : .leading)
        return ZStack {
            if shown {
                WindowSnapIsland(kind: kind, model: host.windowSnap, tileScale: host.rowScale)
                    .transition(.asymmetric(
                        insertion: .modifier(active: bud.hidden, identity: bud.shown)
                            .animation(.bouncy(duration: 0.55, extraBounce: 0.2).delay(left ? 0.1 : 0.15)),
                        removal: .modifier(active: bud.hidden, identity: bud.shown)
                            .animation(.easeIn(duration: 0.16))))
            }
        }
        .frame(width: width, alignment: alignment)
        .padding(.top, host.layout().islandTop)
    }

    /// The picker's tiles leave fast when it closes; arriving, they pop in one by one themselves.
    private static let contentOut = Animation.easeOut(duration: 0.08)

    /// The black shape itself, as wide as what it holds.
    private var notch: some View {
        let size = host.shapeSize
        let silhouette = NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
        return ZStack(alignment: .top) {
            if open {
                // Laid out at the open size from the first frame, so the growing shape uncovers the row
                // while its tiles unfold downward into place.
                WindowSnapView(model: host.windowSnap, tileScale: host.rowScale)
                    .padding(.top, host.layout().rowTop)
                    .padding(.horizontal, WindowSnapPickerLayout.rowInset)
                    .frame(width: host.layout().pickerSize.width, height: host.layout().pickerSize.height, alignment: .top)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(Self.contentOut)))
            }
            if host.stage != .rest {
                // One title for the strip and the open notch: it never fades between them, it only slides
                // as the top corner rounds out, so the strip reads as growing into the picker.
                CameraRow(strip: host.dragStrip, open: open)
                    .padding(.horizontal, SnapHeading.inset(fromCorner: topRadius))
                    .frame(width: size.width, height: host.notchSize.height)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(silhouette.fill(NotchPalette.surfaceBase))
        .clipShape(silhouette)
        .shadow(color: open ? NotchPalette.panelShadow : Color.clear,
                radius: NotchPalette.panelShadowRadius, y: NotchPalette.panelShadowY)
    }
}

/// The row beside the camera: the Layouts title on its left, dimmed on the strip until the drag is on it.
private struct CameraRow: View {
    @ObservedObject var strip: NotchDragStripModel
    let open: Bool

    var body: some View {
        SnapHeading.layouts
            .opacity(open || strip.windowOnTarget ? 1 : 0.75)
            .animation(NotchMotion.fast, value: strip.windowOnTarget)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An island tucked against the notch (small, blurred, clear) or out in its place.
private struct IslandBud {
    let towardNotch: CGFloat
    let anchor: UnitPoint

    var hidden: Modifier { Modifier(shown: false, towardNotch: towardNotch, anchor: anchor) }
    var shown: Modifier { Modifier(shown: true, towardNotch: towardNotch, anchor: anchor) }

    struct Modifier: ViewModifier {
        let shown: Bool
        let towardNotch: CGFloat
        let anchor: UnitPoint

        func body(content: Content) -> some View {
            content
                .scaleEffect(shown ? 1 : 0.35, anchor: anchor)
                .offset(x: shown ? 0 : towardNotch)
                .blur(radius: shown ? 0 : 10)
                .opacity(shown ? 1 : 0)
        }
    }
}
#endif
