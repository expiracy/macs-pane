#if canImport(AppKit)
import SwiftUI
import AppKit
import MacsPaneCore

/// The window-moving engine behind saved presets (`SnapLayout`): applies one to the current desktop's
/// windows (with an Undo live activity and launch-on-apply for closed apps), snapshots the open windows
/// into one, and owns the app-visuals cache the Windows page reads names, icons and bundle ids from.
///
/// Current-desktop only: macOS no longer lets a normal process move a window to another Space via the
/// private window-server APIs (a no-op on recent releases), so a preset places the windows on the
/// desktop you're on.
///
/// Used on the main thread (every entry point is a pointer gesture or a main-queue completion), matching
/// the other notch view models, which is why it isn't marked `@MainActor` (its owner
/// constructs it synchronously).
final class SmartWindowsViewModel {
    /// The layout's windows are moving: present its Undo live activity alongside, wired by `MacsPaneModel`,
    /// with the undo action (which replays the captured pre-apply frames) and the layout.
    var onArranged: ((_ undo: @escaping WindowsUndo, _ layout: SnapLayout) -> Void)?

    private let recents: RecentWindowsService
    private let arranger: WindowArranging
    private let mover: WindowControlService
    private let screenProvider: () -> NSScreen?
    var hostScreen: NSScreen?
    private var targetScreen: NSScreen? { hostScreen ?? screenProvider() }
    private var isArranging = false
    /// App names / icons / bundle ids for the live window roster.
    let visuals = SmartWindowsAppVisuals()

    /// Launches a bound-but-closed app on apply and snaps its window in when it appears.
    private let launchPlacer: SmartWindowsLaunchPlacer

    init(recents: RecentWindowsService,
         arranger: WindowArranging,
         mover: WindowControlService = WindowControlService(),
         launcher: AppLaunching = WorkspaceAppLauncher(),
         screenProvider: @escaping () -> NSScreen? = { NSScreen.notchHost }) {
        self.launchPlacer = SmartWindowsLaunchPlacer(launcher: launcher, arranger: arranger, recents: recents)
        self.recents = recents
        self.arranger = arranger
        self.mover = mover
        self.screenProvider = screenProvider
    }

    // MARK: - Display

    func appName(for pid: Int32) -> String { visuals.appName(for: pid) }
    func icon(for pid: Int32) -> NSImage? { visuals.icon(for: pid) }

    // MARK: - Apply

    /// Apply a saved layout: resolve each region's binding to a window over the current MRU roster, move
    /// them, then collapse with an Undo activity. A `.app` slot whose app isn't open falls back to a
    /// most-recent window (the v1 default). `dragged` is the window a notch drop carried to the top, so
    /// its Undo sends it home.
    func applyLayout(_ layout: SnapLayout, dragged: WindowUndoCapture.DraggedHome? = nil) {
        guard !isArranging else { return }
        guard mover.isAuthorized else { PermissionGrantPresenter.shared.requestAccessibility(); return }
        guard let screen = targetScreen else { return }
        let ranked = recents.orderedRecentWindows(excludingPid: ProcessInfo.processInfo.processIdentifier)
        visuals.cache(for: ranked)   // ensures the bundle ids are populated for resolution
        let plan = SnapLayoutApplier.plan(
            for: layout, rankedWindows: ranked,
            bundleID: { [weak self] in self?.visuals.bundleID(for: $0.ownerPid) },
            visibleFrame: screen.visibleFrame)
        guard !plan.placements.isEmpty || !plan.launchPending.isEmpty else { return }
        // Capture each moved window's frame and stacking BEFORE moving, so Undo can replay it.
        let prior = WindowUndoCapture.priorPlacements(of: plan.placements.map(\.window),
                                                      roster: recents.currentWindows(),
                                                      dragged: dragged,
                                                      primaryHeight: WindowControlService.primaryHeight)
        let front = NSWorkspace.shared.frontmostApplication
        let undo: WindowsUndo = { [arranger] done in arranger.restore(prior, frontmost: front, done: done) }
        if !plan.placements.isEmpty {
            isArranging = true
            arranger.arrange(plan.placements) { [weak self] _ in self?.isArranging = false }
            if !prior.isEmpty { onArranged?(undo, layout) }
        }
        // Closed apps marked launch-on-apply: open each (without stealing focus), then place its window
        // when it appears.
        launchPlacer.beginApply()
        plan.launchPending.forEach(launchPlacer.launchAndPlace)
    }

    // MARK: - Snapshot

    /// All currently-open windows snapshotted, one region per window at its current on-screen position,
    /// bound to its app (`SnapLayoutSnapshotter` holds the geometry), for Settings' "Save current
    /// windows…". Returns nil if none qualify. Caller names + persists.
    func currentWindowsSnapshot(named name: String) -> SnapLayout? {
        guard let screen = targetScreen else { return nil }
        let windows = recents.orderedRecentWindows(excludingPid: ProcessInfo.processInfo.processIdentifier)
        visuals.cache(for: windows)
        return SnapLayoutSnapshotter.snapshot(of: windows, named: name,
                                              visibleFrame: screen.visibleFrame,
                                              primaryHeight: WindowControlService.primaryHeight,
                                              bundleID: { [visuals] in visuals.bundleID(for: $0.ownerPid) },
                                              launch: { _ in true })
    }
}
#endif
