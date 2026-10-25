#if canImport(AppKit)
import Foundation

/// Watches for the Accessibility grant flipping on, macOS often grants trust without a relaunch,
/// so a surface showing a grant state polls and drops the prompt the moment trust lands. The shared
/// copy of the timer dance Smart Windows and Window Snap each hand-rolled (Window Snap's copy can
/// fold into this one the next time its controller sheds a seam).
final class AccessibilityGrantPoller {
    private var timer: Timer?

    /// Begin polling; idempotent, an already-running poll is left alone. `onGrant` fires once, on
    /// the main run loop, and the poll stops itself.
    func start(isGranted: @escaping () -> Bool, onGrant: @escaping () -> Void) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard isGranted() else { return }
            timer.invalidate()
            self.timer = nil
            onGrant()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
#endif
