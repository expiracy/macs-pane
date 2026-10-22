import Foundation

/// One window as reported by the window server (`CGWindowListCopyWindowInfo`), reduced to what
/// the Window Peek needs. A pure value so the picking/ordering logic is testable; the AppKit
/// layer maps the CG dictionaries into it.
public struct ProcessWindowInfo: Identifiable, Equatable, Sendable {
    /// The `CGWindowID` raw value — the capture and AX-join key.
    public let id: UInt32
    public let ownerPid: Int32
    /// Window-server title. Only populated when Screen Recording is granted; `nil` renders as
    /// "Window N" in the peek.
    public let title: String?
    /// Global frame in CG (top-left-origin) coordinates — same space AX reports, no flip needed.
    public let frame: CGRect
    /// False for minimized windows and windows on other Spaces — capture likely fails for these,
    /// so the peek pre-badges them.
    public let isOnScreen: Bool
    public let layer: Int
    public let alpha: Double

    public init(id: UInt32, ownerPid: Int32, title: String?, frame: CGRect,
                isOnScreen: Bool, layer: Int, alpha: Double) {
        self.id = id
        self.ownerPid = ownerPid
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.layer = layer
        self.alpha = alpha
    }
}

/// Selects the windows the peek shows for one app, in z-order.
public enum ProcessWindowPicker {
    /// Anything smaller than this in either dimension is window-chrome debris, not a window a
    /// user would recognise (Chromium drag-image placeholders are 64×64).
    static let minDimension: CGFloat = 80
    /// The chrome-strip signature: Chromium (Brave/Chrome/Electron) keeps tab-strip/toolbar
    /// overlay WINDOWS on the standard layer — full screen-width, ~40–110 pt tall, some parked
    /// above the screen top. A real document window is never this letterboxed.
    static let stripMaxHeight: CGFloat = 120
    static let stripMinAspect: CGFloat = 8

    /// The app's "real" windows: standard layer, visible alpha, and not chrome debris. Verified
    /// against a live Brave dump (one visible window): the real 1800×1130 window passes; its
    /// 1800×109 / 1800×41 toolbar-strip ghosts and 64×64 drag ghost do not — without this,
    /// ghost rows pollute the list and the ✕'s quit-if-last rule never sees a "last" window.
    /// Input order is preserved — `CGWindowListCopyWindowInfo` lists front-to-back, so index 0
    /// is the app's frontmost.
    public static func windows(for pid: Int32, in snapshot: [ProcessWindowInfo]) -> [ProcessWindowInfo] {
        windows(forAnyOf: [pid], in: snapshot)
    }

    /// The same pick across SEVERAL owning pids, still in one front-to-back z-order. An app row can
    /// stand for more than one pid once the rollup absorbs a helper NSWorkspace reported as an app
    /// of its own (see `ProcessRow.absorbedAppPids`) — without this the absorbed pid's windows would
    /// disappear along with its row.
    public static func windows(forAnyOf pids: Set<Int32>,
                               in snapshot: [ProcessWindowInfo]) -> [ProcessWindowInfo] {
        var seen = Set<UInt32>()
        return snapshot.filter { w in
            pids.contains(w.ownerPid) && isRealWindow(w) && seen.insert(w.id).inserted
        }
    }

    /// The one window an APP row's actions should act on — Bring to Front, and the hold-to-peek
    /// preview — chosen from that app's picked windows in front-to-back order.
    ///
    /// Index 0 is the wrong answer. The roster comes from `CGWindowListCopyWindowInfo(.optionAll)`
    /// and `isRealWindow` deliberately ignores `isOnScreen`, so minimized windows and windows parked
    /// on other Spaces sort into the same z-order as visible ones. Measured against a live desktop,
    /// 3 of 5 multi-window apps (WhatsApp, Steam, Steam Helper) had an off-screen window at index 0
    /// — and raising un-minimizes its target, so "Bring to Front" restored a window nobody asked for
    /// while the one on screen stayed put.
    ///
    /// So the target is chosen, not taken: the window you focused most recently wins, since an app
    /// row stands for the window you were actually using. With no focus history at all (nothing in
    /// this app has been touched since launch) it falls back to the frontmost window that is really
    /// ON SCREEN, and only then to plain z-order — an app whose every window is minimized has no
    /// better answer than its first.
    public static func actionTarget(among windows: [ProcessWindowInfo],
                                    lastFocusedByWindow: [UInt32: Date]) -> ProcessWindowInfo? {
        var freshest: (window: ProcessWindowInfo, focused: Date)?
        for window in windows {
            guard let focused = lastFocusedByWindow[window.id] else { continue }
            // Strictly newer, so a tie keeps the frontmost of the two.
            if let freshest, focused <= freshest.focused { continue }
            freshest = (window, focused)
        }
        if let freshest { return freshest.window }
        return windows.first(where: \.isOnScreen) ?? windows.first
    }

    /// Whether one window is a "real" window a user would recognise: standard layer, visible, big
    /// enough, and not a Chromium chrome-strip ghost. The per-window half of `windows(for:in:)`,
    /// exposed so other features (Smart Windows) can apply the same junk filter to a cross-app roster.
    /// Deliberately does NOT consider `isOnScreen` — callers that want only visible windows check that.
    public static func isRealWindow(_ w: ProcessWindowInfo) -> Bool {
        w.layer == 0
            && w.alpha > 0
            && w.frame.width >= minDimension && w.frame.height >= minDimension
            && !isChromeStrip(w.frame)
    }

    private static func isChromeStrip(_ frame: CGRect) -> Bool {
        frame.height < stripMaxHeight && frame.width >= frame.height * stripMinAspect
    }
}
