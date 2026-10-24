#if canImport(AppKit)
import AppKit

/// Manages the lifetime of a global (and optionally local) `NSEvent` monitor, so features that need
/// to *observe* input without consuming it don't each re-implement add/remove. The global monitor
/// sees events headed to other apps; the optional local monitor sees events headed to our own windows
/// (returned unchanged, so they're never swallowed). Permission-free for the mouse events used here.
///
/// This is the shared input primitive the notch hover + window-snap drag both build on, and the seam
/// a future gesture/trackpad-style feature would reuse rather than re-implementing monitor plumbing.
final class GlobalEventMonitor {
    private let mask: NSEvent.EventTypeMask
    private let includeLocal: Bool
    private let handler: (NSEvent) -> Void
    private var globalToken: Any?
    private var localToken: Any?

    init(matching mask: NSEvent.EventTypeMask,
         local includeLocal: Bool = false,
         handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.includeLocal = includeLocal
        self.handler = handler
    }

    func start() {
        guard globalToken == nil else { return }
        globalToken = NSEvent.addGlobalMonitorForEvents(matching: mask) { [handler] event in handler(event) }
        if includeLocal {
            localToken = NSEvent.addLocalMonitorForEvents(matching: mask) { [handler] event in
                handler(event)
                return event        // observe only, never swallow our own events
            }
        }
    }

    func stop() {
        if let globalToken { NSEvent.removeMonitor(globalToken) }
        if let localToken { NSEvent.removeMonitor(localToken) }
        globalToken = nil
        localToken = nil
    }

    deinit { stop() }
}
#endif
