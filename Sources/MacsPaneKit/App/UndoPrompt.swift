#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// The live activity that grows out of the notch after a preset or pairing moves your windows: what
/// happened on the left of the camera, Undo on its right. It bounces out from the notch's own width and
/// its contents spring out from behind the camera; it goes back in by itself after a few seconds (held
/// while the pointer is on it), contents first, and
/// never takes focus from the windows it just arranged. The same Undo stays in the menu's Last change
/// box until it is used.
final class UndoPromptController {
    private var panel: NSPanel?
    private var state: UndoActivityState?
    private var dismiss: DispatchWorkItem?
    private var hovering = false

    static let lifetime: TimeInterval = 8
    /// How far the activity reaches either side of the camera.
    static let wing: CGFloat = 170
    /// Room either side for the opening bounce to overshoot into without being clipped.
    static let overshoot: CGFloat = 24

    func show(title: String, symbol: String, glyph: [SnapGlyphBox]?, on screen: NSScreen?,
              undo: @escaping () -> Void) {
        close(animated: false)
        guard let screen = screen ?? NSScreen.main else { return }
        let notch = screen.notchGeometry.collapsedSize
        let size = CGSize(width: notch.width + 2 * Self.wing, height: notch.height)
        let state = UndoActivityState(notchWidth: notch.width)
        let view = UndoActivityView(title: title, symbol: symbol, glyph: glyph, state: state, size: size,
                                    undo: { [weak self] in
                                        self?.close(animated: true)
                                        undo()
                                    },
                                    hover: { [weak self] inside in self?.hover(inside) })
        let canvas = size.width + 2 * Self.overshoot
        let panel = UndoActivityPanel(contentRect: CGRect(x: screen.frame.midX - canvas / 2,
                                                          y: screen.frame.maxY - size.height,
                                                          width: canvas, height: size.height))
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFrontRegardless()
        self.panel = panel
        self.state = state
        state.open()
        scheduleDismiss()
    }

    /// Tuck back into the notch, then go. A window drag starting closes it at once, so the picker is
    /// never under it.
    func close(animated: Bool = true) {
        dismiss?.cancel()
        dismiss = nil
        hovering = false
        guard let panel else { return }
        self.panel = nil
        let state = self.state
        self.state = nil
        guard animated, let state else { panel.orderOut(nil); return }
        state.shut()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { panel.orderOut(nil) }
    }

    /// The pointer on the activity holds it; leaving starts the countdown again.
    private func hover(_ inside: Bool) {
        hovering = inside
        if inside { dismiss?.cancel() } else { scheduleDismiss() }
    }

    private func scheduleDismiss() {
        dismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hovering else { return }
            self.close()
        }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime, execute: work)
    }
}

/// Above the notch's own panel, clickable for its Undo, and never key: the arranged windows keep focus.
private final class UndoActivityPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
}

/// The activity's two beats: the shape out of the notch, then its contents out from behind the camera
/// (and the reverse on the way back in), so it reads as the notch itself coming alive.
final class UndoActivityState: ObservableObject {
    @Published var isOpen = false
    @Published var showsContent = false
    let notchWidth: CGFloat

    init(notchWidth: CGFloat) { self.notchWidth = notchWidth }

    /// The shape bounces out past its width and settles; a beat later the contents spring out.
    func open() {
        withAnimation(.bouncy(duration: 0.5, extraBounce: 0.18)) { isOpen = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) { self.showsContent = true }
        }
    }

    /// The contents duck back behind the camera, then the shape snaps into the notch.
    func shut() {
        withAnimation(.easeIn(duration: 0.14)) { showsContent = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { self.isOpen = false }
        }
    }
}

/// The activity itself (J1 in the design canvas): the notch widened, the preset's layout and "Coding
/// applied" left of the camera, a blue Undo right of it.
struct UndoActivityView: View {
    let title: String
    let symbol: String
    let glyph: [SnapGlyphBox]?
    @ObservedObject var state: UndoActivityState
    let size: CGSize
    let undo: () -> Void
    let hover: (Bool) -> Void
    @Environment(\.notchMetrics) private var m

    /// How far the contents travel out from behind the camera.
    private static let travel: CGFloat = 34

    var body: some View {
        let shape = NotchShape(topCornerRadius: m.rootTopRadiusCompact, bottomCornerRadius: m.rootBottomRadiusCompact)
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                icon
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(Emerge(shown: state.showsContent, from: Self.travel))
            Spacer(minLength: state.notchWidth + 16)
            Button(action: undo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.accentColor))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Put the windows back where they were")
            .frame(maxWidth: .infinity, alignment: .trailing)
            .modifier(Emerge(shown: state.showsContent, from: -Self.travel))
        }
        .padding(.horizontal, SnapHeading.inset(fromCorner: m.rootTopRadiusCompact))
        .frame(width: size.width, height: size.height)
        .frame(width: state.isOpen ? size.width : state.notchWidth, height: size.height)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .onHover(perform: hover)
        .frame(width: size.width + 2 * UndoPromptController.overshoot, height: size.height, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        // The panel never takes focus; draw Undo as the front window would.
        .environment(\.controlActiveState, .key)
    }

    /// The preset's own layout with its apps when there is one, else the action's symbol.
    @ViewBuilder private var icon: some View {
        if let glyph, !glyph.isEmpty {
            SnapBoxesGlyph(boxes: glyph, aimed: false).frame(width: 24, height: 16)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

/// Contents coming out from behind the camera: from `from` points toward it, small, blurred and
/// clear, to their place, full size and sharp.
private struct Emerge: ViewModifier {
    let shown: Bool
    let from: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: shown ? 0 : from)
            .scaleEffect(shown ? 1 : 0.86)
            .blur(radius: shown ? 0 : 6)
            .opacity(shown ? 1 : 0)
    }
}
#endif
