#if canImport(AppKit)
import AppKit
import ApplicationServices
import MacsPaneCore

/// Resolves a `CGWindowList` window (`ProcessWindowInfo`) to its live `AXUIElement`, so a feature can
/// act on exactly the window it's showing or listing. Resolution order: the private CGWindowID bridge
/// (exact) → a unique exact title → nearest frame (AX and CGWindowList both report top-left global
/// coordinates, so frames compare directly). Shared by the Window Peek (close / raise one window) and
/// Smart Windows (snap a window to its slot).
///
/// Callers must run this off the main thread, it messages the target app's AX server, which can hang;
/// the app element gets a short messaging timeout here so a wedged app is a bounded stall, not a freeze.
enum AXWindowResolver {
    static func resolve(_ target: ProcessWindowInfo) -> AXUIElement? {
        let windows = axWindows(of: target.ownerPid)   // fetched once, shared by both passes
        return exactMatch(target, in: windows) ?? nearestByFrame(target, in: windows)
    }

    private static func exactMatch(_ target: ProcessWindowInfo,
                                   in windows: [AXUIElement]) -> AXUIElement? {
        guard !windows.isEmpty else { return nil }
        if AXWindowBridge.isAvailable,
           let exact = windows.first(where: { AXWindowBridge.windowID(of: $0) == target.id }) {
            return exact
        }
        if let title = target.title {
            let titled = windows.filter { AX.string($0, kAXTitleAttribute as String) == title }
            if titled.count == 1 { return titled[0] }
        }
        return nil
    }

    private static func nearestByFrame(_ target: ProcessWindowInfo,
                                       in windows: [AXUIElement]) -> AXUIElement? {
        windows.min { frameDistance($0, target.frame) < frameDistance($1, target.frame) }
    }

    private static func axWindows(of pid: Int32) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)   // hung app ⇒ bounded stall, off-main
        return AX.elements(appElement, kAXWindowsAttribute as String)
    }

    private static func frameDistance(_ element: AXUIElement, _ frame: CGRect) -> CGFloat {
        guard let pos = AX.point(element, kAXPositionAttribute as String),
              let size = AX.size(element, kAXSizeAttribute as String) else {
            return .greatestFiniteMagnitude
        }
        return abs(pos.x - frame.minX) + abs(pos.y - frame.minY)
            + abs(size.width - frame.width) + abs(size.height - frame.height)
    }
}
#endif
