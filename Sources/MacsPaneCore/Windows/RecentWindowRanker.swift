import Foundation
import CoreGraphics

/// Orders the live window roster "most recently used first" for the Smart Windows picker. Pure, so the
/// ranking is unit-tested without the window server: the AppKit layer hands it a `CGWindowList`
/// snapshot plus the focus tracker's recency maps.
///
/// Recency falls back per window: the window's own last-focus time, else its app's last-activation
/// time, else the distant past (never touched this session — sinks below anything that was). Ties
/// (equal instants, or both never-focused) break by the window server's front-to-back order, which the
/// input preserves, so the result is stable from one open to the next.
public enum RecentWindowRanker {
    /// The eligible windows, most-recently-used first. Keeps non-junk on-screen windows the user would
    /// recognise (the same real-window filter as `ProcessWindowPicker`) and drops `excludingPid` — our
    /// own app, so the notch panel can never be a candidate.
    public static func ranked(windows: [ProcessWindowInfo],
                              recencyByWindow: [UInt32: Date],
                              recencyByApp: [Int32: Date],
                              excludingPid: Int32) -> [ProcessWindowInfo] {
        windows
            .enumerated()
            .filter { _, w in
                w.ownerPid != excludingPid && w.isOnScreen && ProcessWindowPicker.isRealWindow(w)
            }
            .sorted { lhs, rhs in
                let lr = recency(of: lhs.element, byWindow: recencyByWindow, byApp: recencyByApp)
                let rr = recency(of: rhs.element, byWindow: recencyByWindow, byApp: recencyByApp)
                if lr != rr { return lr > rr }
                return lhs.offset < rhs.offset   // front-to-back tiebreak keeps the order stable
            }
            .map(\.element)
    }

    private static func recency(of w: ProcessWindowInfo,
                                byWindow: [UInt32: Date],
                                byApp: [Int32: Date]) -> Date {
        byWindow[w.id] ?? byApp[w.ownerPid] ?? .distantPast
    }
}
