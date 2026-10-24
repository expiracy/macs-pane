#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// The Magnet-style "ghost" of where the window will land: one translucent, accent-tinted rounded
/// rect at the target frame, shown full-screen while a snap zone is highlighted. Lives on its own
/// click-through overlay panel (`SnapPreviewPanel`) so it covers the screen without eating the drag.
/// Styling matches the notch's drop-target language (accent fill at low opacity + accent stroke,
/// continuous corners).
struct SnapPreviewOverlay: View {
    @ObservedObject var model: WindowSnapViewModel
    /// The host screen's frame (AppKit bottom-left), used to map the target rect into the view's
    /// top-left space.
    let screenFrame: CGRect
    // Hosted on its own screen-sized panel (no `notchScale` injected) → these resolve at the base
    // scale, i.e. the ghost is a fixed screen-space overlay that doesn't grow with the text preset.
    @Environment(\.notchMetrics) private var m

    var body: some View {
        ZStack {
            if let target = model.previewFrame {
                RoundedRectangle(cornerRadius: m.radiusSurface, style: .continuous)
                    .fill(NotchPalette.dropGhostFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: m.radiusSurface, style: .continuous)
                            .strokeBorder(NotchPalette.strokeAccent, lineWidth: m(3))   // bold ghost edge (heavier than the m.thick ladder)
                    }
                    .notchShadow(.high)
                    .frame(width: target.width, height: target.height)
                    // AppKit bottom-left → SwiftUI top-left within this screen.
                    .position(x: target.midX - screenFrame.minX,
                              y: screenFrame.maxY - target.midY)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(NotchMotion.fast, value: model.previewFrame)
        .ignoresSafeArea()
    }
}

/// A borderless, click-through, non-activating overlay panel that hosts the snap ghost. Sits just
/// below the notch panel (`mainMenu + 3`) so the picker stays on top, but above ordinary windows so
/// the ghost reads as an overlay. Reuses `NotchPanel`'s recipe, minus any input (it never takes clicks).
final class SnapPreviewPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
#endif
