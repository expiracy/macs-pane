#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// Live state for one grant card: whether the permission has landed, the deep link, and the escape
/// for a stale System Settings entry.
final class PermissionGrantModel: ObservableObject {
    @Published var granted: Bool
    let grant: PermissionGrant
    private let isGranted: () -> Bool
    private let prompt: (() -> Void)?
    private let poller = AccessibilityGrantPoller()
    private var onGranted: (() -> Void)?
    var onClose: (() -> Void)?

    init(grant: PermissionGrant, isGranted: @escaping () -> Bool, prompt: (() -> Void)? = nil) {
        self.grant = grant
        self.isGranted = isGranted
        self.prompt = prompt
        self.granted = isGranted()
    }

    func openSettings() {
        guard let url = grant.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func close() { onClose?() }

    /// Drop the entry macOS holds for this app, so a switch left on by an earlier copy of the app
    /// stops shadowing this one, then ask again and reopen the list.
    func startOver() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        // Bounded, because this runs on the MAIN thread from a click: an unbounded `waitUntilExit`
        // on a wedged `tccutil` is a beachball with no way out. It normally answers in milliseconds.
        let outcome = BoundedProcess.run("/usr/bin/tccutil", ["reset", grant.tccService, bundleID],
                                         timeout: 5, captureOutput: false)
        if outcome.timedOut {
            NSLog("MacsPane: tccutil reset %@ for %@ did not finish — carrying on", grant.tccService, bundleID)
        }
        prompt?()
        openSettings()
    }

    /// Watch for the switch being flipped; `onGranted` fires once, after a beat on screen so the
    /// card can show that it noticed.
    func watch(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
        guard !granted else { return }
        poller.start(isGranted: { [isGranted] in isGranted() }) { [weak self] in
            guard let self else { return }
            self.granted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { self.onGranted?() }
        }
    }

    func stop() { poller.stop() }
}
#endif
