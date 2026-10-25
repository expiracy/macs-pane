#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// Detects a window being dragged toward the notch and snaps it on release. Uses three observe-only
/// global mouse monitors (the permission-free `NSEvent` pattern), we never *consume* events, so the OS's native window drag is untouched; we only
/// *also* snap when the user lets go over a picker tile. The actual move goes through `WindowControlService`
/// (the one part that needs Accessibility). Owned by `MacsPaneNotchController`; the owner feeds it the live notch screen + panel frame so
/// the drag pointer can be hit-tested against the on-screen tiles, and the notch it drives is a
/// `WindowSnapHosting`.
final class WindowSnapController {
    private let host: WindowSnapHosting
    private let mover = WindowControlService()
    /// Places a pairing's windows (the dragged window + recent partners) when a suggestion tile is the
    /// release target, the same Accessibility arranger Smart Windows uses.
    private let arranger = AXWindowArranger()
    private var config: WindowSnapConfig

    /// The notch screen + panel frame (AppKit bottom-left), set by `MacsPaneNotchController` on build /
    /// screen change. The panel frame maps the screen-space drag pointer into the tiles' space.
    private var notchScreen: NSScreen?
    private var notchPanelFrame: CGRect?
    /// Cached pure geometry for the notch screen, rebuilt only when the screen reconfigures (in
    /// `updateNotchGeometry`), so the per-event drag hot path doesn't re-derive it from `NSScreen`
    /// (re-deriving it per `.leftMouseDragged` frame is what made dragging a window feel laggy).
    private var notchGeometry: NotchGeometry?

    private let preview: SnapPreviewPresenter

    private enum DragState {
        case idle
        case armed(GrabbedWindow, downAt: CGPoint)   // pressed on a title bar, not yet dragging
        case dragging(GrabbedWindow)                 // dragging; the notch opens only near it
    }
    private var state: DragState = .idle
    /// Whether the drag pointer is currently inside the notch hot-zone (we've asked the view model to
    /// open). The *actual* expansion is delayed by the global dwell and read back from `host.isSnapPickerOpen`;
    /// this only tracks enter/leave so we fire `setPointerInside`/preview exactly once per crossing.
    private var pointerInHotZone = false

    /// A mouse-down whose title-bar classification FAILED but which may still be a window drag. The AX
    /// hit-test at the down instant is occasionally transient, the target app is momentarily busy, or
    /// the window hasn't front-raised yet, so a single rejected down would otherwise kill the whole
    /// gesture (the "snapping sometimes doesn't detect my drag" report). We retry the grab at the same
    /// point on the first few drag events; cleared once we arm, on mouse-up, or when the pointer wanders
    /// too far from the press to still be a title-bar drag.
    private var pendingGrab: (point: CGPoint, attemptsLeft: Int)?

    /// The grabbed window's frame (CG/AX top-left) at the moment it was grabbed, its pre-drag home. Held
    /// so a pairing's Undo restores the dragged window to where it started, not to wherever it had been
    /// dragged by the time it was released over a pairing tile (a release-time snapshot catches it mid-drag).
    private var grabbedHomeFrame: CGRect?

    /// Re-grab budget after a failed down (see `pendingGrab`) and the travel (pt) past which we stop
    /// retrying, beyond it the gesture is clearly content/text dragging, not a window move.
    private static let regrabAttempts = 3
    private static let regrabAbandonDistance: CGFloat = 60

    private var dragMonitors: [GlobalEventMonitor] = []
    private var authPoll: Timer?

    /// Asks the panel controller to host the notch on the screen under this point (it then feeds the
    /// new screen back through `updateNotchGeometry`). A drag emits no `.mouseMoved`, so the hover
    /// monitor can't move the panel, the drag does, so the target is on the screen you're dragging on.
    var followPointer: ((CGPoint) -> Void)?
    /// The screen the current snap session's zones, pairings and ghost were built for.
    private var sessionScreen: NSScreen?

    /// Fired when Accessibility trust flips to granted (so the menu/settings can refresh).
    var onAuthorizationChange: (() -> Void)?

    init(host: WindowSnapHosting, config: WindowSnapConfig) {
        self.host = host
        self.config = config
        self.preview = SnapPreviewPresenter(model: host.windowSnap)
    }

    var isAuthorized: Bool { mover.isAuthorized }

    // MARK: - Lifecycle

    func activate() {
        guard config.enabled else { return }
        installMonitors()
        startAuthPollIfNeeded()
    }

    func deactivate() {
        removeMonitors()
        stopAuthPoll()
        preview.tearDown()
        host.windowSnap.cancel()
        host.setWindowDragActive(false)
        pointerInHotZone = false
        pendingGrab = nil
        grabbedHomeFrame = nil
        sessionScreen = nil
        state = .idle
    }

    func updateConfig(_ newConfig: WindowSnapConfig) {
        let wasEnabled = config.enabled
        config = newConfig
        if newConfig.enabled && !wasEnabled {
            activate()
        } else if !newConfig.enabled && wasEnabled {
            deactivate()
        }
        startAuthPollIfNeeded()
    }

    /// Provided by `MacsPaneNotchController` whenever the panel is (re)built for a screen. Caches the notch
    /// geometry here so the per-event drag hot path needn't re-derive it from `NSScreen`.
    func updateNotchGeometry(screen: NSScreen?, panelFrame: CGRect?) {
        notchScreen = screen
        notchPanelFrame = panelFrame
        notchGeometry = screen?.notchGeometry
    }

    // MARK: - Authorization

    /// Surface the system prompt and open the Accessibility pane. Called from explicit user actions
    /// (enabling snapping, the "Grant access" button), never on the mouse-down hot path.
    func requestAuthorization() {
        PermissionGrantPresenter.shared.requestAccessibility()
        startAuthPollIfNeeded()
    }

    private func startAuthPollIfNeeded() {
        guard config.enabled, !mover.isAuthorized, authPoll == nil else { return }
        // macOS often flips trust without a relaunch; poll so the UI updates the moment it's granted.
        authPoll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.mover.isAuthorized {
                timer.invalidate()
                self.authPoll = nil
                self.onAuthorizationChange?()
            }
        }
    }

    private func stopAuthPoll() {
        authPoll?.invalidate()
        authPoll = nil
    }

    // MARK: - Mouse monitors

    private func installMonitors() {
        guard dragMonitors.isEmpty else { return }
        // Observe-only global monitors (never consumed), so the OS's native window drag is untouched.
        dragMonitors = [
            GlobalEventMonitor(matching: [.leftMouseDown]) { [weak self] _ in self?.handleDown() },
            GlobalEventMonitor(matching: [.leftMouseDragged]) { [weak self] _ in self?.handleDragged() },
            GlobalEventMonitor(matching: [.leftMouseUp]) { [weak self] _ in self?.handleUp() },
        ]
        dragMonitors.forEach { $0.start() }
    }

    private func removeMonitors() {
        dragMonitors.forEach { $0.stop() }
        dragMonitors = []
    }

    private func handleDown() {
        pendingGrab = nil
        grabbedHomeFrame = nil
        guard config.enabled, mover.isAuthorized, !host.windowSnap.pickerLayouts.isEmpty else {
            SnapDebug.log("down ignored: enabled=\(config.enabled) authorized=\(mover.isAuthorized)")
            state = .idle
            return
        }
        let p = NSEvent.mouseLocation
        guard let grabbed = mover.grabbedWindow(atScreenPoint: p,
                                                titleBarBandHeight: CGFloat(config.titleBarBandHeight)) else {
            SnapDebug.log("down \(SnapDebug.fmt(p)): not a snappable window title bar (will retry on drag)")
            state = .idle
            pendingGrab = (p, Self.regrabAttempts)   // give a transient AX miss a few chances on the drag
            return
        }
        SnapDebug.log("down \(SnapDebug.fmt(p)): armed on pid \(grabbed.pid)")
        state = .armed(grabbed, downAt: p)
        grabbedHomeFrame = mover.axFrame(of: grabbed.element)   // capture the home now, before any drag
    }

    private func handleDragged() {
        let p = NSEvent.mouseLocation
        switch state {
        case .armed(let grabbed, let downAt):
            evaluateArm(p, grabbed: grabbed, downAt: downAt)
        case .dragging(let grabbed):
            followDrag(grabbed, to: p)
            evaluateProximity(p)
        case .idle:
            retryPendingGrab(at: p)
        }
    }

    /// Start tracking once the pointer has actually travelled past the activation threshold from the
    /// press, so a plain click never arms a drag.
    private func evaluateArm(_ p: CGPoint, grabbed: GrabbedWindow, downAt: CGPoint) {
        let travel = p.distance(to: downAt)
        SnapDebug.log("drag while armed: travel \(Int(travel))/\(config.dragActivationDistance)pt")
        if travel >= CGFloat(config.dragActivationDistance) {
            SnapDebug.log("drag passed \(config.dragActivationDistance)pt threshold: tracking")
            startTracking(grabbed, at: p)
            evaluateProximity(p)              // in case the drag began right on the notch
        }
    }

    /// Re-attempt a grab that the mouse-down rejected, at the original press point, on the first few drag
    /// events, recovering a transient AX hit-test miss. On success we arm and immediately evaluate the
    /// current travel (a drag already past the threshold starts tracking at once); we give up once the
    /// attempts run out or the pointer has wandered too far from the press to be a title-bar drag.
    private func retryPendingGrab(at p: CGPoint) {
        guard config.enabled, mover.isAuthorized, var pending = pendingGrab else { return }
        if p.distance(to: pending.point) > Self.regrabAbandonDistance { pendingGrab = nil; return }
        pending.attemptsLeft -= 1
        pendingGrab = pending.attemptsLeft > 0 ? pending : nil
        guard let grabbed = mover.grabbedWindow(atScreenPoint: pending.point,
                                                titleBarBandHeight: CGFloat(config.titleBarBandHeight)) else {
            return
        }
        SnapDebug.log("re-grab succeeded at \(SnapDebug.fmt(pending.point)): armed late on pid \(grabbed.pid)")
        pendingGrab = nil
        state = .armed(grabbed, downAt: pending.point)
        grabbedHomeFrame = mover.axFrame(of: grabbed.element)   // home (a few pt into the drag on this path)
        evaluateArm(p, grabbed: grabbed, downAt: pending.point)
    }

    private func handleUp() {
        pendingGrab = nil
        guard case .dragging(let grabbed) = state else { state = .idle; return }
        // Commit only if the pointer was over the notch on a highlighted tile (end() returns nil
        // otherwise). So letting go anywhere but on the open picker is a harmless no-op. `end()`
        // deliberately leaves the picker rendering, we clear it below, after the collapse.
        let commit = host.windowSnap.end()
        switch commit {
        case .zone(_, let frame), .layoutBox(let frame):
            mover.snap(grabbed.element, to: frame)
        case .preset(let id):
            // The preset's Undo sends the dragged window back to where it was grabbed, not to the notch
            // where this release leaves it. Applied after the release has finished landing the window.
            let roster = host.recents.currentWindows()
            let home = WindowSnapSuggestions.draggedHome(grabbed, home: grabbedHomeFrame,
                                                         currentFrame: mover.axFrame(of: grabbed.element),
                                                         roster: roster)
            DispatchQueue.main.async { [host] in host.applyPreset(id, dragged: home) }
        case .pairing(let placements):
            // Capture every window's pre-tiling frame and stacking so the Undo activity can replay it,
            // then tile. The dragged window is slot 0, so the arranger moves it alongside the partners
            // (one uniform tiling, no separate snap for the grabbed element), and its home is where it
            // was grabbed: by release it is mid-drag at the notch.
            let home = placements.first.flatMap { slot in
                grabbedHomeFrame.map { WindowUndoCapture.DraggedHome(windowID: slot.window.id, frame: $0) }
            }
            let prior = WindowUndoCapture.priorPlacements(of: placements.map(\.window),
                                                          roster: host.recents.currentWindows(),
                                                          dragged: home,
                                                          primaryHeight: WindowControlService.primaryHeight)
            let front = NSWorkspace.shared.frontmostApplication
            let undo: WindowsUndo? = prior.isEmpty ? nil : { [arranger] done in
                arranger.restore(prior, frontmost: front, done: done)
            }
            arranger.arrange(placements, completion: nil)
            if let undo { host.offerPairingUndo(undo) }
        case nil:
            break
        }
        if commit != nil { host.windowSnapped() }
        let pickerWasOpen = host.isSnapPickerOpen
        host.setWindowDragActive(false)
        preview.hide()
        pointerInHotZone = false
        grabbedHomeFrame = nil
        sessionScreen = nil
        state = .idle

        if pickerWasOpen {
            // Collapse immediately, straight from the picker (no leave-delay), and clear the snap state
            // only once the close animation has carried the picker off-screen, so the resting tab page
            // never flashes between the selection and the close. Skip the reset if a fresh drag has
            // already begun a new snap session (it owns `windowSnap` now).
            host.collapseSnapPicker { [weak self] in
                guard let self, case .idle = self.state else { return }
                self.host.windowSnap.cancel()
            }
        } else {
            // The picker never opened (released before dwelling on the notch): drop any pending dwell-open
            // so it can't pop the picker after release, then clear the snap state. Crucially we do NOT
            // force the surface off here, `setWindowDragActive(false)` above already shrinks the drag
            // target through `closeSurface`, whose guard keeps the black drawn when a live cue (the meeting
            // strip) is at rest. (Trampling `surfaceVisible` here left that cue with a see-through bg.)
            host.cancelPendingHoverTransitions()
            host.windowSnap.cancel()
        }
    }

    /// Start watching a confirmed window drag. The notch widens into a drag target right away (so the
    /// user has something easy to aim at) but does NOT expand into the picker yet, that happens only
    /// once the pointer reaches the notch and dwells there (`evaluateProximity`).
    private func startTracking(_ grabbed: GrabbedWindow, at p: CGPoint) {
        followPointer?(p)                     // the target widens on the screen the drag is on
        guard let screen = notchScreen, !host.windowSnap.pickerLayouts.isEmpty else { state = .idle; return }
        state = .dragging(grabbed)
        beginSession(grabbed, on: screen)
        host.setWindowDragActive(true)
    }

    /// The drag crossed onto another screen while the notch is still collapsed: bring the target with
    /// it and rebuild the session for that screen, so a release there snaps onto THAT screen. An open
    /// picker is left where it is, leaving its zone collapses it first, like the hover.
    private func followDrag(_ grabbed: GrabbedWindow, to p: CGPoint) {
        guard !host.isSnapPickerOpen else { return }
        followPointer?(p)
        guard let screen = notchScreen, screen !== sessionScreen else { return }
        preview.hide()
        beginSession(grabbed, on: screen)
    }

    /// Build the snap session, zones, pairing suggestions, ghost, for one screen.
    private func beginSession(_ grabbed: GrabbedWindow, on screen: NSScreen) {
        sessionScreen = screen
        let ownPid = Int32(ProcessInfo.processInfo.processIdentifier)
        let suggestions = WindowSnapSuggestions.build(
            for: grabbed,
            roster: host.recents.orderedRecentWindows(excludingPid: ownPid),
            grabbedFrame: mover.axFrame(of: grabbed.element),
            visibleFrame: screen.visibleFrame)
        host.windowSnap.begin(visibleFrame: screen.visibleFrame, suggestions: suggestions)
        // Build the full-screen ghost now, while the drag is still away from the notch, so crossing
        // into the notch region only has to *reveal* it, not allocate a screen-sized view mid-drag
        // (that allocation, on every entry, is what made the crossing hitch/"jump").
        if config.showFullScreenPreview { preview.prepare(on: screen) }
    }

    /// Drive the notch from the drag pointer: when it enters the (notch-centred) hot-zone, ask the
    /// view model to open, which waits out the global dwell before expanding into the picker, and
    /// when it leaves, collapse. The hot-zone tracks the notch's *actual* expansion (`host.isSnapPickerOpen`),
    /// growing to the picker footprint once open so the pointer can travel down onto the tiles. While
    /// open, highlight the tile under the pointer.
    private func evaluateProximity(_ p: CGPoint) {
        // `notchGeometry` is cached (see `updateNotchGeometry`), so this per-drag-frame hit-test doesn't
        // re-query the screen's safe-area insets on every mouse move.
        guard let screen = notchScreen, let geo = notchGeometry else { return }
        let expanded = host.isSnapPickerOpen
        let hotZone = windowSnapHotZone(geo, expanded: expanded)
        let inside = NSMouseInRect(p, hotZone, false)
        host.setWindowOnTarget(inside && !expanded)   // collapsed, the hot zone IS the strip
        SnapDebug.log("pointer \(SnapDebug.fmt(p)) zone \(SnapDebug.fmt(hotZone)) inside=\(inside) " +
                      "expanded=\(expanded) inHotZone=\(pointerInHotZone)")

        if inside {
            if !pointerInHotZone {
                pointerInHotZone = true
                if config.showFullScreenPreview { preview.show(on: screen) }
            }
            // Feed the live pointer every event so the dwell restarts unless the cursor holds still,
            // sliding a window through the zone won't open the picker; only pausing at the notch will.
            host.setPointerInside(true, at: p)
        } else if pointerInHotZone {
            pointerInHotZone = false
            host.setPointerInside(false, at: nil)
            preview.hide()
        }

        if expanded {
            updatePointer(p)
        } else {
            host.windowSnap.clearHighlight()
        }
    }

    /// The zone the drag pointer must reach for the picker to open. Collapsed, it matches the *visible*
    /// widened notch exactly, the full widened width, but only the notch's own height, so the cursor
    /// has to be ON the black notch (shoved up against the top edge), not under the menu bar below it.
    /// What you see is what you hit. Paired with the view model's stillness dwell, a deliberate pause on
    /// the notch is what opens it. Once open it becomes the picker footprint (plus slack) so the pointer
    /// can travel down onto the tiles without collapsing.
    private func windowSnapHotZone(_ geo: NotchGeometry, expanded: Bool) -> CGRect {
        expanded
            ? geo.windowSnapExpandedZone(size: host.snapPickerSize, slack: 24)
            : geo.windowSnapCollapsedZone(targetWidth: host.windowDragTargetSize.width)
    }

    private func updatePointer(_ p: CGPoint) {
        guard let panelFrame = notchPanelFrame else { return }
        // Screen point (AppKit bottom-left) → notch-panel-local (top-left origin at the panel's
        // top-left), matching the coordinate space the picker tiles report their frames in.
        let local = CGPoint(x: p.x - panelFrame.minX, y: panelFrame.maxY - p.y)
        host.windowSnap.pointerMoved(toPanelLocal: local)
    }
}
#endif
