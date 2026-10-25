#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// Owns the full-screen snap ghost for `WindowSnapController`: built for one screen, rebuilt only
/// when the drag moves to another, revealed while the pointer is on the notch.
final class SnapPreviewPresenter {
    private let model: WindowSnapViewModel
    private var panel: SnapPreviewPanel?
    /// The screen frame the current host view was built for, so the screen-sized `NSHostingView`
    /// is rebuilt only on an actual screen change, never on every notch entry.
    private var screenFrame: CGRect?

    init(model: WindowSnapViewModel) {
        self.model = model
    }

    /// Build the ghost panel if it's missing or the screen changed, but do NOT order it front (that's
    /// `show`'s job). Split out so the screen-sized `NSHostingView` is allocated up front (when the
    /// drag starts) rather than at the instant the drag crosses into the notch. The SwiftUI view
    /// observes the snap model and updates itself as the highlighted zone changes, so it never needs
    /// recreating to reflect the pointer, only on a genuine screen change.
    func prepare(on screen: NSScreen) {
        guard panel == nil || screenFrame != screen.frame else { return }
        let panel = panel ?? SnapPreviewPanel(screen: screen)
        panel.setFrame(screen.frame, display: false)
        panel.contentView = NSHostingView(rootView: SnapPreviewOverlay(model: model, screenFrame: screen.frame))
        self.panel = panel
        screenFrame = screen.frame
    }

    func show(on screen: NSScreen) {
        prepare(on: screen)                   // no-op if already built for this screen, just reveal it
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Drop the ghost entirely; it's rebuilt on the next drag.
    func tearDown() {
        hide()
        panel = nil
        screenFrame = nil
    }
}
#endif
