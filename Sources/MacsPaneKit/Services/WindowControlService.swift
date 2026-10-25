#if canImport(AppKit)
import AppKit
import ApplicationServices
import MacsPaneCore

/// Authorization seam so the rest of the app can ask "can we drive other apps' windows?" without
/// importing the Accessibility C API. `WindowControlService` is the only conformer; tests/mocks could
/// provide another. (Mirrors how `SymbolicHotKeyBackend` abstracts the private CGS API.)
protocol AccessibilityAuthorizing: AnyObject {
    var isAuthorized: Bool { get }
    @discardableResult func requestAuthorization(prompt: Bool) -> Bool
}

/// A window grabbed by its title bar, ready to be snapped.
struct GrabbedWindow {
    let element: AXUIElement
    let pid: pid_t
}

/// Moves and resizes *other* apps' windows via the Accessibility API, the one part of MacsPane that
/// needs the Accessibility (TCC) grant. Three jobs: (1) report/req​uest authorization; (2) classify
/// the window under the pointer at mouse-down (is it a real window's title bar?); (3) snap a window
/// to a target frame. All coordinates cross the AppKit(bottom-left) ⇄ AX(top-left) boundary through
/// `AXCoordinateConverter`, anchored on the primary screen's height.
final class WindowControlService: AccessibilityAuthorizing {

    // MARK: Authorization

    var isAuthorized: Bool { AXIsProcessTrusted() }

    /// Read trust, optionally surfacing the system prompt (deep-links to Privacy & Security →
    /// Accessibility). Only ever called from explicit user actions, never on the mouse-down hot path.
    @discardableResult
    func requestAuthorization(prompt: Bool) -> Bool {
        // Literal key == `kAXTrustedCheckOptionPrompt`; used directly to avoid the Unmanaged<CFString>
        // import differences across SDKs.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings at the Accessibility pane so the user can grant access.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Classification (mouse-down)

    /// The window whose title bar is under `pAppKit` (AppKit bottom-left screen coords), or `nil` if
    /// the press isn't on a snappable window's title bar. This is what distinguishes a window drag
    /// from a text selection, a content drag, or a file drag: the press must land in the top
    /// `titleBarBandHeight` points of a standard/dialog window that isn't already full-screen.
    func grabbedWindow(atScreenPoint pAppKit: CGPoint, titleBarBandHeight: CGFloat) -> GrabbedWindow? {
        guard isAuthorized else { SnapDebug.log("grab rejected: not AX-authorized"); return nil }
        let pAX = AXCoordinateConverter.flipPoint(pAppKit, primaryHeight: Self.primaryHeight)

        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)   // a hung target app can't stall the press
        var hit: AXUIElement?
        let axErr = AXUIElementCopyElementAtPosition(system, Float(pAX.x), Float(pAX.y), &hit)
        guard axErr == .success, let element = hit else {
            SnapDebug.log("grab rejected: hit-test failed at AX \(SnapDebug.fmt(pAX)) (err \(axErr.rawValue))")
            return nil
        }
        guard let window = enclosingWindow(of: element) else {
            SnapDebug.log("grab rejected: no enclosing window; hit role=\(copyString(element, kAXRoleAttribute) ?? "?") subrole=\(copyString(element, kAXSubroleAttribute) ?? "?")")
            return nil
        }

        // Only standard/dialog windows snap (rejects menus, popovers, the Dock, our own panels).
        let subrole = copyString(window, kAXSubroleAttribute)
        guard subrole == (kAXStandardWindowSubrole as String) || subrole == (kAXDialogSubrole as String) else {
            SnapDebug.log("grab rejected: window subrole=\(subrole ?? "nil") (not standard/dialog)")
            return nil
        }

        // A native-fullscreen window can't be tiled, don't arm on it.
        if isTrue(window, "AXFullScreen") { SnapDebug.log("grab rejected: window is native-fullscreen"); return nil }

        // The press must be in the title-bar band (top of the window's AX frame), not the content.
        guard let pos = copyPoint(window, kAXPositionAttribute),
              let size = copySize(window, kAXSizeAttribute) else {
            SnapDebug.log("grab rejected: couldn't read window pos/size")
            return nil
        }
        let band = CGRect(x: pos.x, y: pos.y, width: size.width, height: titleBarBandHeight)
        guard band.contains(pAX) else {
            SnapDebug.log("grab rejected: AX \(SnapDebug.fmt(pAX)) below title-bar band \(SnapDebug.fmt(band)); window pos \(SnapDebug.fmt(pos)) size \(SnapDebug.fmt(size)), bandH \(Int(titleBarBandHeight))")
            return nil
        }

        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        SnapDebug.log("grab accepted: pid \(pid) subrole=\(subrole ?? "?") pos \(SnapDebug.fmt(pos)) size \(SnapDebug.fmt(size)) band \(SnapDebug.fmt(band))")
        return GrabbedWindow(element: window, pid: pid)
    }

    // MARK: Focused window (shortcuts)

    /// The window you are typing in: the front app's focused window, if it is a standard or dialog
    /// window that isn't full-screen. Nil when MacsPane itself is in front, or nothing is focused.
    func focusedWindow() -> GrabbedWindow? {
        guard isAuthorized, let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)   // a hung app can't stall the key press
        guard let window = copyElement(app, kAXFocusedWindowAttribute) else { return nil }
        let subrole = copyString(window, kAXSubroleAttribute)
        guard subrole == (kAXStandardWindowSubrole as String) || subrole == (kAXDialogSubrole as String),
              !isTrue(window, "AXFullScreen") else { return nil }
        return GrabbedWindow(element: window, pid: front.processIdentifier)
    }

    /// The window's current AX frame in CG/AX top-left global coordinates, the same space
    /// `ProcessWindowInfo.frame` reports, so a grabbed window can be matched against the live roster by
    /// position. `nil` if the element doesn't expose position/size.
    func axFrame(of element: AXUIElement) -> CGRect? {
        guard let pos = copyPoint(element, kAXPositionAttribute),
              let size = copySize(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    // MARK: Move (mouse-up)

    /// Snap `window` to `frameAppKit` (AppKit bottom-left). Returns whether the window ended up
    /// roughly where asked. One move then one resize lands most windows, and each resize makes the app
    /// redraw, which with several windows at once loads the whole screen; only a window that didn't
    /// land gets size→position→size→position, which defeats apps that clamp a size to the screen
    /// they are on. Falls back to move-only for windows whose size isn't settable.
    @discardableResult
    func snap(_ window: AXUIElement, to frameAppKit: CGRect) -> Bool {
        let target = AXCoordinateConverter.flipRect(frameAppKit, primaryHeight: Self.primaryHeight)
        let canResize = isSettable(window, kAXSizeAttribute)

        setPoint(window, kAXPositionAttribute, target.origin)
        if canResize { setSize(window, kAXSizeAttribute, target.size) }

        // Verify; AX writes can silently fail or be clamped, so never trust the return code. Read the
        // window back and, if it didn't land within tolerance, write it the long way.
        if !landed(window, at: target, canResize: canResize) {
            applyFrame(window, position: target.origin, size: target.size, resize: canResize)
        }
        return landed(window, at: target, canResize: canResize)
    }

    /// Whether `window`'s current AX frame matches `target` (top-left coords) within 2pt. Position is
    /// always checked; size only when the window is resizable (we move-only otherwise).
    private func landed(_ window: AXUIElement, at target: CGRect, canResize: Bool) -> Bool {
        let pos = copyPoint(window, kAXPositionAttribute) ?? .zero
        let size = copySize(window, kAXSizeAttribute) ?? target.size
        let posOff = pos.distance(to: target.origin)
        let sizeOff = canResize ? hypot(size.width - target.size.width, size.height - target.size.height) : 0
        return posOff <= 2 && sizeOff <= 2
    }

    private func applyFrame(_ window: AXUIElement, position: CGPoint, size: CGSize, resize: Bool) {
        if resize { setSize(window, kAXSizeAttribute, size) }
        setPoint(window, kAXPositionAttribute, position)
        if resize { setSize(window, kAXSizeAttribute, size) }
        setPoint(window, kAXPositionAttribute, position)
    }

    // MARK: - AX helpers

    // The primary (menu-bar) display's height, the anchor for the AppKit⇄AX Y-flip. Use the main
    // display id directly rather than `NSScreen.screens.first` (whose "primary" ordering isn't
    // contractually guaranteed across display rearrangement).
    static var primaryHeight: CGFloat { CGDisplayBounds(CGMainDisplayID()).height }

    /// Resolve the `AXWindow` that contains `element`. Apps expose their windows inconsistently, the
    /// element under a title bar is often an `AXStaticText` (the title) or a toolbar item with no clean
    /// parent chain up to the window, so a single parent walk wrongly rejected real windows. Try
    /// several routes, accepting the first whose role is actually `AXWindow`:
    ///   1. the element already *is* a window;
    ///   2. its `kAXWindowAttribute`, the window directly containing it;
    ///   3. its `kAXTopLevelUIElementAttribute`, the top-level element, normally the window;
    ///   4. a bounded climb up `kAXParentAttribute` (the original heuristic, as a last resort).
    /// Returns nil only when none resolves, genuinely not a window.
    private func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        if isWindow(element) { return element }
        if let w = copyElement(element, kAXWindowAttribute), isWindow(w) { return w }
        if let w = copyElement(element, kAXTopLevelUIElementAttribute), isWindow(w) { return w }
        var current: AXUIElement? = element
        var hops = 0
        while let e = current, hops < 12 {
            if isWindow(e) { return e }
            guard let parent = copyElement(e, kAXParentAttribute) else { return nil }
            current = parent
            hops += 1
        }
        return nil
    }

    private func isWindow(_ el: AXUIElement) -> Bool {
        copyString(el, kAXRoleAttribute) == (kAXWindowRole as String)
    }

    private func copyRaw(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref
    }

    private func copyString(_ el: AXUIElement, _ attr: String) -> String? { copyRaw(el, attr) as? String }

    /// Copy an attribute whose value is itself an `AXUIElement` (a parent, window, or top-level
    /// element), returning nil if it's absent or not an element.
    private func copyElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        guard let ref = copyRaw(el, attr), CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private func isTrue(_ el: AXUIElement, _ attr: String) -> Bool {
        guard let ref = copyRaw(el, attr), CFGetTypeID(ref) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue((ref as! CFBoolean))
    }

    private func copyPoint(_ el: AXUIElement, _ attr: String) -> CGPoint? {
        guard let ref = copyRaw(el, attr), CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        guard AXValueGetValue((ref as! AXValue), .cgPoint, &p) else { return nil }
        return p
    }

    private func copySize(_ el: AXUIElement, _ attr: String) -> CGSize? {
        guard let ref = copyRaw(el, attr), CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        guard AXValueGetValue((ref as! AXValue), .cgSize, &s) else { return nil }
        return s
    }

    private func setPoint(_ el: AXUIElement, _ attr: String, _ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(el, attr as CFString, v) }
    }

    private func setSize(_ el: AXUIElement, _ attr: String, _ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(el, attr as CFString, v) }
    }

    private func isSettable(_ el: AXUIElement, _ attr: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(el, attr as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

}
#endif
