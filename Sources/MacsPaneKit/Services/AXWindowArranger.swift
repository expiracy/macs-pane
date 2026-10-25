#if canImport(AppKit)
import AppKit
import ApplicationServices
import MacsPaneCore

/// Live `WindowArranging`: moves each selected window to its slot via Accessibility. For every
/// placement it resolves the CGWindowList window to its AX element (`AXWindowResolver`), un-minimizes
/// it if needed, snaps it (`WindowControlService`, the verified, retry-checked move/resize), and marks
/// it main/raised. All AX messaging runs off the main thread (apps can hang); afterwards it activates
/// each app on the main thread in reverse slot order, so the layout surfaces above other windows and
/// the most-recently-used window (slot 1) ends up frontmost. `completion` reports how many landed.
final class AXWindowArranger: WindowArranging {
    private let mover: WindowControlService
    private let queue = DispatchQueue(label: "macpp.smartWindows.ax", qos: .userInitiated)

    init(mover: WindowControlService = WindowControlService()) {
        self.mover = mover
    }

    func arrange(_ placements: [WindowTilePlacement], completion: ((Int) -> Void)?) {
        guard !placements.isEmpty else { DispatchQueue.main.async { completion?(0) }; return }
        queue.async { [mover] in
            guard AXIsProcessTrusted() else { DispatchQueue.main.async { completion?(0) }; return }
            var landed = 0
            var moved: [AXUIElement] = []
            for placement in placements {
                guard let element = AXWindowResolver.resolve(placement.window) else { continue }
                if AX.bool(element, kAXMinimizedAttribute as String) {
                    AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
                if mover.snap(element, to: placement.frame) { landed += 1 }
                moved.append(element)
            }
            // Raised from the last slot to the first, so within each app the first slot ends on top.
            for element in moved.reversed() {
                AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            }
            DispatchQueue.main.async {
                // Reverse order so slot 1 (most recent) activates last and ends frontmost; the slots
                // don't overlap, so every arranged window stays visible regardless.
                for placement in placements.reversed() {
                    NSRunningApplication(processIdentifier: placement.window.ownerPid)?
                        .activate(from: .current, options: [])
                }
                completion?(landed)
            }
        }
    }
}

/// Puts windows back where a move found them, calling `done` once they have landed.
typealias WindowsUndo = (_ done: @escaping () -> Void) -> Void

extension WindowArranging {
    /// Put windows back for an Undo: `prior` front-to-back as they were stacked, so the one that was
    /// in front ends in front, then `frontmost`, the app that was in front before the move (often one
    /// whose windows weren't moved at all), is brought forward again. `done` runs once they have landed.
    func restore(_ prior: [WindowTilePlacement], frontmost: NSRunningApplication?, done: @escaping () -> Void) {
        arrange(prior) { _ in
            if let frontmost, frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               !frontmost.isTerminated {
                frontmost.activate(from: .current, options: [])
            }
            done()
        }
    }
}
#endif
