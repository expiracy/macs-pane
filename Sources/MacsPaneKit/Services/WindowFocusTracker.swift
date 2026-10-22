#if canImport(AppKit)
import AppKit
import ApplicationServices
import CoreGraphics

/// Recency tracker behind the Processes list's "Last Used" column (ported from the App Manager
/// branch's LRU tracker). Runs for the whole notch-module lifetime — purely event-driven, never
/// polling — because the data must exist BEFORE the tab is first opened. Two layers:
///  • NSWorkspace app-activation (cheap, no AX) stamps per-app recency;
///  • a per-app `AXObserver` (push notifications) tells us *which window* gained focus, so the
///    column is per-window precise. Without the Accessibility grant only the app layer runs.
///
/// Recency is in-memory / session-scoped: `CGWindowID`s aren't stable across relaunch, so
/// persisting would mis-attribute history. The maps are pruned against the live roster each
/// publish via `prune(liveWindows:livePids:)`.
final class WindowFocusTracker {
    /// Last-focused time per window — the primary signal.
    private var lastFocused: [UInt32: Date] = [:]
    /// Last-activated time per app — the fallback for windows with no per-window history yet.
    private var appRecency: [Int32: Date] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var appElements: [pid_t: AXUIElement] = [:]

    private var activateToken: NSObjectProtocol?
    private var launchToken: NSObjectProtocol?
    private var terminateToken: NSObjectProtocol?
    private var running = false

    // MARK: Lifecycle

    func start() {
        guard !running else { return }
        running = true
        let wnc = NSWorkspace.shared.notificationCenter
        activateToken = wnc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                        object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.handleActivated(app)
            }
        }
        launchToken = wnc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                      object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.installObserver(for: app)
            }
        }
        terminateToken = wnc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                         object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.teardownObserver(pid: app.processIdentifier)
            }
        }
        for app in NSWorkspace.shared.runningApplications where Self.isTracked(app) {
            installObserver(for: app)
        }
        if let front = NSWorkspace.shared.frontmostApplication { handleActivated(front) }
    }

    func stop() {
        guard running else { return }
        running = false
        let wnc = NSWorkspace.shared.notificationCenter
        [activateToken, launchToken, terminateToken].compactMap { $0 }.forEach(wnc.removeObserver)
        activateToken = nil; launchToken = nil; terminateToken = nil
        for pid in Array(observers.keys) { teardownObserver(pid: pid) }
        lastFocused.removeAll(); appRecency.removeAll()
    }

    deinit { stop() }

    // MARK: Reading

    /// Copies for the sampling pipeline (the VM passes them into the pure composer).
    func snapshot() -> (byWindow: [UInt32: Date], byApp: [Int32: Date]) {
        (lastFocused, appRecency)
    }

    /// Drop entries for windows/apps that no longer exist, so the maps can't grow unbounded.
    func prune(liveWindows: Set<UInt32>, livePids: Set<Int32>) {
        lastFocused = lastFocused.filter { liveWindows.contains($0.key) }
        appRecency = appRecency.filter { livePids.contains($0.key) }
    }

    // MARK: Workspace handlers

    /// The Processes list shows windowed apps AND menu-bar agents, so both are tracked (the
    /// sibling tracker was `.regular`-only).
    private static func isTracked(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular || app.activationPolicy == .accessory
    }

    private func handleActivated(_ app: NSRunningApplication) {
        guard Self.isTracked(app) else { return }
        let pid = app.processIdentifier
        appRecency[pid] = Date()
        installObserver(for: app)
        stampFocusedWindow(pid: pid)   // activation may not emit a window-changed notification
    }

    private func stampFocusedWindow(pid: pid_t) {
        guard AXIsProcessTrusted(), let appEl = appElements[pid] ?? makeAppElement(pid),
              let focused = AX.element(appEl, kAXFocusedWindowAttribute as String),
              let wid = AXWindowBridge.windowID(of: focused) else { return }
        lastFocused[wid] = Date()
    }

    // MARK: AXObserver

    private func makeAppElement(_ pid: pid_t) -> AXUIElement? {
        if let el = appElements[pid] { return el }
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.25)
        appElements[pid] = el
        return el
    }

    private func installObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard Self.isTracked(app), observers[pid] == nil, AXIsProcessTrusted(),
              let appEl = makeAppElement(pid) else { return }

        // C callback: derive the pid from the notifying element, then re-read its focused window.
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<WindowFocusTracker>.fromOpaque(refcon).takeUnretainedValue()
            tracker.stampFocusedWindow(pid: AX.pid(of: element))
        }

        var observer: AXObserver?
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for note in [kAXFocusedWindowChangedNotification,
                     kAXMainWindowChangedNotification,
                     kAXApplicationActivatedNotification] {
            AXObserverAddNotification(observer, appEl, note as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func teardownObserver(pid: pid_t) {
        if let observer = observers[pid] {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers[pid] = nil
        appElements[pid] = nil
        appRecency[pid] = nil
    }
}
#endif
