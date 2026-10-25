#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// The always-on window-recency source, shared by the Processes tab (its "Last Used" column) and Smart
/// Windows (its picker order). Owns the module-lifetime `WindowFocusTracker`, started/stopped with the
/// notch MODULE, not any tab, because the recency must exist BEFORE either surface is first opened, plus
/// a `WindowListProvider` for the live `CGWindowList` roster.
///
/// `recencySnapshot`/`prune` are the passthrough the Processes sampling pipeline calls on every tick;
/// `orderedRecentWindows` is the Smart Windows read, the live roster ranked most-recently-used first.
final class RecentWindowsService {
    private let tracker = WindowFocusTracker()
    private let windowProvider = WindowListProvider()

    func start() { tracker.start() }
    func stop() { tracker.stop() }

    /// Recency maps for the Processes sampling pipeline (fed into `ProcessEntryComposer`).
    func recencySnapshot() -> (byWindow: [UInt32: Date], byApp: [Int32: Date]) { tracker.snapshot() }

    /// Drop recency for windows/apps no longer live, so the maps can't grow unbounded, called from the
    /// Processes sample, which already computes the live roster.
    func prune(liveWindows: Set<UInt32>, livePids: Set<Int32>) {
        tracker.prune(liveWindows: liveWindows, livePids: livePids)
    }

    /// The live windows, most-recently-used first, for the Smart Windows picker: a fresh `CGWindowList`
    /// snapshot ranked by recency, keeping real on-screen windows and dropping `excludingPid` (our own
    /// app). Computed on demand when the picker opens.
    func orderedRecentWindows(excludingPid: Int32) -> [ProcessWindowInfo] {
        let recency = tracker.snapshot()
        return RecentWindowRanker.ranked(windows: tileableRoster(),
                                         recencyByWindow: recency.byWindow,
                                         recencyByApp: recency.byApp,
                                         excludingPid: excludingPid)
    }

    /// The snapshot narrowed to windows a user would tile: owned by a REGULAR app (Dock presence,
    /// drops background agents' layer-0 surfaces) and actually landing on a display (drops helper
    /// windows parked at extreme off-screen coordinates that still report as on-screen).
    private func tileableRoster() -> [ProcessWindowInfo] {
        let primaryHeight = WindowControlService.primaryHeight
        // NSScreen frames are AppKit bottom-left; flip into the CG top-left space window bounds use.
        let displays = NSScreen.screens.map {
            AXCoordinateConverter.flipRect($0.frame, primaryHeight: primaryHeight)
        }
        var regularByPid: [Int32: Bool] = [:]
        return windowProvider.snapshot().filter { window in
            let regular = regularByPid[window.ownerPid] ?? {
                let policy = NSRunningApplication(processIdentifier: window.ownerPid)?.activationPolicy
                let isRegular = policy == .regular
                regularByPid[window.ownerPid] = isRegular
                return isRegular
            }()
            return regular && WindowScreenCoverage.intersectsAnyDisplay(window.frame, displays: displays)
        }
    }

    /// Every live window front-to-back at its current frame (CG top-left global), a fresh snapshot
    /// used to capture the pre-arrange layout and stacking just before MacsPane moves them, so it can undo.
    func currentWindows() -> [ProcessWindowInfo] { windowProvider.snapshot() }
}
#endif
