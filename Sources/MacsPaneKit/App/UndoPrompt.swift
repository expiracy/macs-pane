#if canImport(AppKit)
import AppKit
import QuartzCore
import SwiftUI
import MacsPaneCore

/// The live activity that grows out of the notch after a preset or pairing moves your windows: what
/// happened on the left of the camera, Undo on its right. It bounces out from the notch's own width and
/// its contents spring out from behind the camera; it goes back in by itself after a few seconds (held
/// while the pointer is on it), contents first, and never takes focus from the windows it just arranged.
final class UndoPromptController {
    /// One panel for the whole session, built at launch (`prepare`) and left on screen: invisible and
    /// click-through while idle, so showing an Undo only starts its animation. Putting a window on
    /// screen as the windows were moving cost the opening its first frames.
    private var panel: UndoActivityPanel?
    private var activity: UndoActivityLayers?
    private var showing = false
    private var dismiss: DispatchWorkItem?
    private var settle: DispatchWorkItem?
    private var hovering = false

    static let lifetime: TimeInterval = 8
    /// How far the activity reaches either side of the camera.
    static let wing: CGFloat = 170
    /// Room either side for the opening bounce to overshoot into without being clipped.
    static let overshoot: CGFloat = 24
    /// The beat after an Undo's windows have landed before the activity tucks away. Moving several
    /// windows makes macOS hold the whole display while the Dock, WindowManager and the resized apps
    /// catch up, and an animation under that stalls.
    static let settleTime: TimeInterval = 0.2

    func prepare() {
        guard panel == nil, let screen = NSScreen.notchHost ?? NSScreen.main else { return }
        let activity = UndoActivityLayers()
        let panel = UndoActivityPanel(contentRect: .zero)
        panel.contentView = activity
        self.panel = panel
        self.activity = activity
        activity.configure(title: "", symbol: "square.grid.2x2", glyph: nil,
                           notch: screen.notchGeometry.collapsedSize, undo: {}, hover: { _ in })
        place(on: screen)
        idle()
        panel.orderFrontRegardless()
    }

    /// `undo` puts the windows back and says when they have landed; the activity tucks away after.
    func show(title: String, symbol: String, glyph: [SnapGlyphBox]?, on screen: NSScreen?,
              undo: @escaping WindowsUndo) {
        close(animated: false)
        guard let screen = screen ?? NSScreen.main else { return }
        prepare()
        guard let panel, let activity else { return }
        activity.configure(title: title, symbol: symbol, glyph: glyph, notch: screen.notchGeometry.collapsedSize,
                           undo: { [weak self] in
                               self?.dismiss?.cancel()
                               undo {
                                   DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleTime) {
                                       self?.close(animated: true)
                                   }
                               }
                           },
                           hover: { [weak self] inside in self?.hover(inside) })
        place(on: screen)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        showing = true
        // Opened a frame later, once the closed shape is on screen, so the bounce plays from its start.
        DispatchQueue.main.async { [weak self, weak activity] in
            guard self?.showing == true else { return }
            activity?.open()
        }
        scheduleDismiss()
    }

    /// Tuck back into the notch, then go idle. A window drag starting closes it at once, so the
    /// picker is never under it.
    func close(animated: Bool = true) {
        dismiss?.cancel()
        dismiss = nil
        settle?.cancel()
        settle = nil
        hovering = false
        guard let activity else { return }
        let wasShowing = showing
        showing = false
        guard animated, wasShowing else { idle(); return }
        activity.shut()
        let work = DispatchWorkItem { [weak self] in self?.idle() }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Invisible, click-through and closed, ready for the next Undo.
    private func idle() {
        panel?.alphaValue = 0
        panel?.ignoresMouseEvents = true
        activity?.reset()
    }

    /// Centred under the camera of `screen`, at the top.
    private func place(on screen: NSScreen) {
        guard let panel, let activity else { return }
        let canvas = activity.canvasSize
        let frame = CGRect(x: screen.frame.midX - canvas.width / 2, y: screen.frame.maxY - canvas.height,
                           width: canvas.width, height: canvas.height)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
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
        animationBehavior = .none   // no fade or zoom of its own: the activity animates itself
    }

    override var canBecomeKey: Bool { false }
}

/// The activity drawn with Core Animation. Its springs run in the system's renderer: driven by
/// SwiftUI they were worked out frame by frame on the main thread, and a frame that reached the screen
/// a little late showed as a stutter. A black notch-shaped layer springs out from the notch's width;
/// the two halves of its content (what happened, Undo), SwiftUI views each, come out from behind the
/// camera: from `travel` points toward it, small, blurred and clear, to their place. Closing is the
/// same in reverse, contents first.
final class UndoActivityLayers: NSView {
    private let shape = UndoShapeView()
    private let clip = UndoClipView()
    private let titleView = NSHostingView(rootView: UndoActivityTitle(title: "", symbol: "", glyph: nil))
    private let buttonView = NSHostingView(rootView: UndoActivityButton(undo: {}))
    private var hover: (Bool) -> Void = { _ in }
    private var notchWidth: CGFloat = 0
    private var isOpen = false
    private(set) var canvasSize: CGSize = .zero
    private let m = EnvironmentValues().notchMetrics

    /// How far the contents travel out from behind the camera.
    private static let travel: CGFloat = 34

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(shape)
        addSubview(clip)
        for view in [titleView, buttonView] as [NSView] {
            view.wantsLayer = true
            view.layerUsesCoreImageFilters = true
            clip.addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Lay out one activity, closed: the shape at the notch's width, its contents hidden.
    func configure(title: String, symbol: String, glyph: [SnapGlyphBox]?, notch: CGSize,
                   undo: @escaping () -> Void, hover: @escaping (Bool) -> Void) {
        self.hover = hover
        notchWidth = notch.width
        let width = notch.width + 2 * UndoPromptController.wing
        canvasSize = CGSize(width: width + 2 * UndoPromptController.overshoot, height: notch.height)
        frame = CGRect(origin: .zero, size: canvasSize)
        shape.frame = bounds
        clip.frame = bounds
        titleView.rootView = UndoActivityTitle(title: title, symbol: symbol, glyph: glyph)
        buttonView.rootView = UndoActivityButton(undo: undo)
        let inset = SnapHeading.inset(fromCorner: m.rootTopRadiusCompact)
        let edge = UndoPromptController.overshoot + inset
        let side = (width - notch.width - 16) / 2 - inset   // the room either side of the camera
        let titleSize = titleView.fittingSize
        let buttonSize = buttonView.fittingSize
        titleView.frame = CGRect(x: edge, y: (notch.height - titleSize.height) / 2,
                                 width: min(titleSize.width, side), height: titleSize.height)
        buttonView.frame = CGRect(x: canvasSize.width - edge - buttonSize.width,
                                  y: (notch.height - buttonSize.height) / 2,
                                  width: buttonSize.width, height: buttonSize.height)
        setAccessibilityLabel(title)
        reset()
    }

    /// Closed, at once: the notch's width, nothing showing.
    func reset() {
        isOpen = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [shape.layer, clip.mask, titleView.layer, buttonView.layer] { layer?.removeAllAnimations() }
        shape.shapeLayer.path = path(width: notchWidth)
        clip.mask.path = path(width: notchWidth)
        reveal(titleView, shown: false, from: Self.travel, timing: nil)
        reveal(buttonView, shown: false, from: -Self.travel, timing: nil)
        CATransaction.commit()
    }

    /// The shape bounces out past its width and settles; a beat later the contents spring out. Once
    /// they are sharp their blur filters go, so the open activity costs no extra drawing pass.
    func open() {
        isOpen = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.isOpen else { return }
            self.titleView.contentFilters = []
            self.buttonView.contentFilters = []
        }
        let full = path(width: canvasSize.width - 2 * UndoPromptController.overshoot)
        let bounce = Timing.spring(duration: 0.5, bounce: 0.48, delay: 0)
        change(shape.shapeLayer, "path", to: full, timing: bounce)
        change(clip.mask, "path", to: full, timing: bounce)
        let out = Timing.spring(duration: 0.42, bounce: 0.32, delay: 0.08)
        reveal(titleView, shown: true, from: Self.travel, timing: out)
        reveal(buttonView, shown: true, from: -Self.travel, timing: out)
        CATransaction.commit()
    }

    /// The contents duck back behind the camera, then the shape snaps into the notch.
    func shut() {
        isOpen = false
        let duck = Timing.easeIn(duration: 0.14)
        reveal(titleView, shown: false, from: Self.travel, timing: duck)
        reveal(buttonView, shown: false, from: -Self.travel, timing: duck)
        let closed = path(width: notchWidth)
        let snap = Timing.spring(duration: 0.34, bounce: 0.2, delay: 0.1)
        change(shape.shapeLayer, "path", to: closed, timing: snap)
        change(clip.mask, "path", to: closed, timing: snap)
    }

    // MARK: - Animating

    private enum Timing {
        case spring(duration: Double, bounce: Double, delay: Double)
        case easeIn(duration: Double)
    }

    /// The notch's silhouette `width` wide, centred on the camera.
    private func path(width: CGFloat) -> CGPath {
        let rect = CGRect(x: (canvasSize.width - width) / 2, y: 0, width: width, height: canvasSize.height)
        return NotchShape(topCornerRadius: m.rootTopRadiusCompact, bottomCornerRadius: m.rootBottomRadiusCompact)
            .path(in: rect).cgPath
    }

    /// One half of the content at its place (`shown`) or tucked toward the camera: moved, shrunk about
    /// its centre, blurred and clear.
    private func reveal(_ view: NSView, shown: Bool, from offset: CGFloat, timing: Timing?) {
        guard let layer = view.layer else { return }
        let size = layer.bounds.size
        let centre = CGPoint(x: (0.5 - layer.anchorPoint.x) * size.width, y: (0.5 - layer.anchorPoint.y) * size.height)
        var hidden = CATransform3DMakeTranslation(offset + centre.x, centre.y, 0)
        hidden = CATransform3DScale(hidden, 0.86, 0.86, 1)
        hidden = CATransform3DTranslate(hidden, -centre.x, -centre.y, 0)
        let values: [(String, Any)] = [("transform", NSValue(caTransform3D: shown ? CATransform3DIdentity : hidden)),
                                       ("opacity", shown ? 1 as Float : 0 as Float)]
        for (keyPath, value) in values {
            if let timing { change(layer, keyPath, to: value, timing: timing) } else { layer.setValue(value, forKeyPath: keyPath) }
        }
        // The blur is the view's own filter (AppKit puts a layer's filters back from it), set to where
        // it ends and animated there from where it shows now.
        let radius: CGFloat = shown ? 0 : 6
        let showing = ((layer.presentation() ?? layer).value(forKeyPath: Self.blurRadius) as? CGFloat) ?? 0
        view.contentFilters = [Self.blur(radius)]
        if let timing { change(layer, Self.blurRadius, from: showing, to: radius, timing: timing) }
    }

    private static let blurRadius = "filters.blur.inputRadius"

    private static func blur(_ radius: CGFloat) -> CIFilter {
        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.name = "blur"
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return filter
    }

    /// Set `keyPath` to `value` and animate there from `from`, else from where it shows now.
    private func change(_ layer: CALayer, _ keyPath: String, from: Any? = nil, to value: Any, timing: Timing) {
        let animation: CABasicAnimation
        var delay: Double = 0
        switch timing {
        case let .spring(duration, bounce, wait):
            let spring = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
            spring.duration = spring.settlingDuration
            animation = spring
            delay = wait
        case let .easeIn(duration):
            animation = CABasicAnimation()
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        }
        animation.keyPath = keyPath
        animation.fromValue = from ?? (layer.presentation() ?? layer).value(forKeyPath: keyPath)
        animation.toValue = value
        if delay > 0 {
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if from == nil { layer.setValue(value, forKeyPath: keyPath) }
        CATransaction.commit()
        layer.add(animation, forKey: keyPath)
    }

    // MARK: - Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hover(true) }
    override func mouseExited(with event: NSEvent) { hover(false) }
}

/// The black silhouette, its own layer so Core Animation can spring its path.
private final class UndoShapeView: NSView {
    override var isFlipped: Bool { true }
    var shapeLayer: CAShapeLayer { layer as! CAShapeLayer }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        shapeLayer.fillColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func makeBackingLayer() -> CALayer { CAShapeLayer() }
}

/// Clips the contents to the silhouette as it grows, through a mask that springs with it.
private final class UndoClipView: NSView {
    let mask = CAShapeLayer()
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.mask = mask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        mask.frame = bounds
    }
}

/// Left of the camera: the preset's own layout with its apps (else the action's symbol) and what
/// happened.
struct UndoActivityTitle: View {
    let title: String
    let symbol: String
    let glyph: [SnapGlyphBox]?

    var body: some View {
        HStack(spacing: 8) {
            if let glyph, !glyph.isEmpty {
                SnapBoxesGlyph(boxes: glyph, aimed: false).frame(width: 24, height: 16)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Right of the camera: the blue Undo.
struct UndoActivityButton: View {
    let undo: () -> Void

    var body: some View {
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
        // The panel never takes focus; draw Undo as the front window would.
        .environment(\.controlActiveState, .key)
    }
}
#endif
