#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// Applies a saved layout's launch-on-apply regions: an app bound to a region that isn't running gets
/// opened (without stealing focus, the snap happens behind the closing notch), then its window is snapped
/// into the region once it actually exists.
///
/// Split out of `SmartWindowsViewModel`: this is a small state machine with a lifetime of its own (a
/// launch, then a retry loop against the live roster) that outlives the apply gesture which started it.
///
/// Best-effort by design, a launch that never shows a window quietly gives up rather than blocking or
/// erroring, matching the notch's degrade-don't-crash rule. Main-thread only, like its owner.
final class SmartWindowsLaunchPlacer {
    /// How long to wait for a freshly-launched app to put a window on screen (~5s at 0.4s a poll).
    private static let maxAttempts = 12
    private static let pollInterval: TimeInterval = 0.4

    private let launcher: AppLaunching
    private let arranger: WindowArranging
    private let recents: RecentWindowsService
    /// Window ids already placed by the in-flight pass, so two same-app launch regions don't both grab the
    /// same window. Cleared at the start of each apply.
    private var placed: Set<UInt32> = []

    init(launcher: AppLaunching, arranger: WindowArranging, recents: RecentWindowsService) {
        self.launcher = launcher
        self.arranger = arranger
        self.recents = recents
    }

    /// Start a fresh apply, resets the per-apply placed-set so distinct windows fill distinct regions.
    func beginApply() { placed.removeAll() }

    /// Launch a bound-but-closed app, then snap its window into the region once it appears.
    func launchAndPlace(_ pending: LaunchPending) {
        launcher.launchApp(bundleID: pending.bundleID) { [weak self] pid in
            guard let pid else { return }
            self?.placeWindow(ofPid: pid, into: pending.frame)
        }
    }

    /// Poll the live window roster for a window owned by a just-launched `pid`, then snap it. A fresh
    /// window can take a moment to exist, so retry briefly before giving up.
    private func placeWindow(ofPid pid: Int32, into frame: CGRect, attempt: Int = 0) {
        let roster = recents.orderedRecentWindows(excludingPid: ProcessInfo.processInfo.processIdentifier)
        if let window = roster.first(where: { $0.ownerPid == pid && !placed.contains($0.id) }) {
            placed.insert(window.id)
            arranger.arrange([WindowTilePlacement(window: window, frame: frame)], completion: nil)
        } else if attempt < Self.maxAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in
                self?.placeWindow(ofPid: pid, into: frame, attempt: attempt + 1)
            }
        }
    }
}
#endif
