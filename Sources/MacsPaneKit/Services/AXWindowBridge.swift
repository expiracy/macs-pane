#if canImport(AppKit)
import ApplicationServices
import CoreGraphics
import Darwin

/// Bridges an `AXUIElement` to its `CGWindowID` via the private `_AXUIElementGetWindow` symbol (the
/// "yabai trick"), the only way to correlate an AX window with the CGWindowList roster, which the
/// Window Peek needs to act on exactly the window it is showing. Resolved at runtime with `dlsym`
/// (against `RTLD_DEFAULT`, since ApplicationServices is already linked) so a future macOS that
/// drops the symbol degrades gracefully, `windowID(of:)` returns nil and matching falls back to
/// title/frame heuristics, rather than failing to launch.
///
/// ⚠️ Private API, grounds for **Mac App Store** rejection. MacsPane ships ad-hoc / Developer-ID +
/// notarized, which does not scan for private API, so it's fine for this distribution model.
enum AXWindowBridge {
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindow: GetWindowFn? = {
        // RTLD_DEFAULT (-2 on Darwin) searches every loaded image for the symbol.
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: GetWindowFn.self)
    }()

    /// The CoreGraphics window id backing `element`, or nil if the bridge symbol or window is gone.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let fn = getWindow else { return nil }
        var wid = CGWindowID(0)
        guard fn(element, &wid) == .success, wid != 0 else { return nil }
        return wid
    }

    /// Whether the private bridge resolved, lets matching code know only heuristics are left.
    static var isAvailable: Bool { getWindow != nil }
}
#endif
