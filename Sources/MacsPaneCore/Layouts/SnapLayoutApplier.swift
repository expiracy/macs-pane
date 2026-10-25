import CoreGraphics

/// Resolves a `SnapLayout` into a plan: the window placements to make now, plus any bound apps that
/// aren't open and are marked launch-on-apply (the AppKit driver launches those, waits for a window,
/// then places them). Pure and deterministic, the driver supplies the ranked roster + a pid→bundle-id
/// lookup and hands the placements to the same `WindowArranging` port Smart Windows uses. Slot order is
/// honoured and no window is placed twice.
public enum SnapLayoutApplier {
    public static func plan(for layout: SnapLayout,
                            rankedWindows: [ProcessWindowInfo],
                            bundleID: (ProcessWindowInfo) -> String?,
                            visibleFrame: CGRect) -> SnapLayoutPlan {
        var used: Set<UInt32> = []
        var placements: [WindowTilePlacement] = []
        var launchPending: [LaunchPending] = []
        for slot in layout.slots {
            if slot.isRemoved { continue }
            let frame = slot.region.frame(in: visibleFrame)
            switch slot.binding {
            case .empty:
                continue
            case .mostRecent:
                if let window = rankedWindows.first(where: { !used.contains($0.id) }) {
                    used.insert(window.id)
                    placements.append(WindowTilePlacement(window: window, frame: frame))
                }
            case .app(let target):
                if let window = rankedWindows.first(where: { !used.contains($0.id) && bundleID($0) == target }) {
                    used.insert(window.id)
                    placements.append(WindowTilePlacement(window: window, frame: frame))
                } else if slot.launchIfClosed {
                    // App isn't open and we're asked to launch it, defer to the driver.
                    launchPending.append(LaunchPending(bundleID: target, frame: frame))
                }
                // else: the app isn't open and we're not launching it → leave this region blank
                // (no surprise window). Use `.mostRecent` for a region that should take any window.
            }
        }
        return SnapLayoutPlan(placements: placements, launchPending: launchPending)
    }
}

/// The outcome of resolving a layout: windows to place now, and closed apps to launch then place.
public struct SnapLayoutPlan: Equatable, Sendable {
    public let placements: [WindowTilePlacement]
    public let launchPending: [LaunchPending]

    public init(placements: [WindowTilePlacement], launchPending: [LaunchPending]) {
        self.placements = placements
        self.launchPending = launchPending
    }
}

/// A bound app that wasn't open at apply time: launch it, wait for its window, then snap it to `frame`.
public struct LaunchPending: Equatable, Sendable {
    public let bundleID: String
    public let frame: CGRect

    public init(bundleID: String, frame: CGRect) {
        self.bundleID = bundleID
        self.frame = frame
    }
}
