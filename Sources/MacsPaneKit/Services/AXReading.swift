#if canImport(AppKit)
import ApplicationServices

/// Shared Accessibility read helpers, the value-unwrapping vocabulary `WindowControlService`
/// keeps private, lifted to one place so AX-driven features (Window Peek's per-window actions,
/// and the App Manager branch when it lands) share a copy instead of re-deriving the CFTypeID
/// dance. (On an App Manager merge, its identical `Notch/AppManager/AXReading.swift` copy should
/// be deleted in favour of this one.)
enum AX {
    static func copyRaw(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String? { copyRaw(el, attr) as? String }

    static func bool(_ el: AXUIElement, _ attr: String) -> Bool {
        guard let ref = copyRaw(el, attr), CFGetTypeID(ref) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue((ref as! CFBoolean))
    }

    static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        guard let ref = copyRaw(el, attr), CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    /// Copy an attribute that holds an array of `AXUIElement` (e.g. `kAXWindowsAttribute`). Done at
    /// the CFArray level with `unsafeBitCast` to dodge flaky `[AXUIElement]` bridging.
    static func elements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
        elementsIfReadable(el, attr) ?? []
    }

    /// Like `elements`, but nil when the read itself failed (error, timeout, wrong type), callers
    /// that treat a genuinely empty array as evidence need the difference.
    static func elementsIfReadable(_ el: AXUIElement, _ attr: String) -> [AXUIElement]? {
        guard let ref = copyRaw(el, attr), CFGetTypeID(ref) == CFArrayGetTypeID() else { return nil }
        let array = ref as! CFArray
        let count = CFArrayGetCount(array)
        var out: [AXUIElement] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(array, i) else { continue }
            out.append(unsafeBitCast(raw, to: AXUIElement.self))
        }
        return out
    }

    static func point(_ el: AXUIElement, _ attr: String) -> CGPoint? {
        guard let ref = copyRaw(el, attr), CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        guard AXValueGetValue((ref as! AXValue), .cgPoint, &p) else { return nil }
        return p
    }

    static func size(_ el: AXUIElement, _ attr: String) -> CGSize? {
        guard let ref = copyRaw(el, attr), CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        guard AXValueGetValue((ref as! AXValue), .cgSize, &s) else { return nil }
        return s
    }

    static func pid(of el: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        return pid
    }
}
#endif
