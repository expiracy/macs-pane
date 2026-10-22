#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// The one way MacsPane asks for a system permission: a small floating window that stays above System
/// Settings, walks the steps, and — for the panes with an app list — hands over the app icon to drag
/// straight into it. Every needs-access surface calls this instead of opening the pane on its own.
public final class PermissionGrantPresenter: NSObject, NSWindowDelegate {
    public static let shared = PermissionGrantPresenter()

    private var window: NSWindow?
    private var model: PermissionGrantModel?

    /// Show the helper for `grant`. `isGranted` is polled so the window can confirm and close itself;
    /// `prompt` is the app's own one-shot system prompt, used first when it is still available.
    public func present(_ grant: PermissionGrant, isGranted: @escaping () -> Bool,
                        prompt: (() -> Void)? = nil, openPane: Bool = true,
                        onGranted: (() -> Void)? = nil) {
        guard !isGranted() else { onGranted?(); return }
        prompt?()
        close()
        let model = PermissionGrantModel(grant: grant, isGranted: isGranted, prompt: prompt)
        model.onClose = { [weak self] in self?.close() }
        self.model = model
        let view = PermissionGrantView(grant: grant, appName: Self.appName, appURL: Bundle.main.bundleURL,
                                       model: model)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]   // the window follows the content's height
        let window = NSWindow(contentViewController: hosting)
        window.title = "\(grant.title) access"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating                    // stays reachable while System Settings is in front
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        position(window)
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if openPane { model.openSettings() }
        model.watch { [weak self] in
            onGranted?()
            self?.close()
        }
    }

    public func close() {
        model?.stop()
        model = nil
        window?.delegate = nil
        window?.close()
        window = nil
        restoreActivationPolicy()
    }

    /// Down the left edge of the screen with the notch, so the System Settings window it opens
    /// (centred) never lands on top of the icon you have to drag out of here.
    private func position(_ window: NSWindow) {
        guard let screen = NSScreen.main else { window.center(); return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.minX + 24,
                                      y: visible.midY - size.height / 2))
    }

    public func windowWillClose(_ notification: Notification) {
        model?.stop()
        model = nil
        window = nil
        restoreActivationPolicy()
    }

    /// Back to menu-bar-only, unless another MacsPane window (Settings, setup) is still open.
    private func restoreActivationPolicy() {
        let others = NSApp.windows.contains { $0.isVisible && $0 !== window && $0.canBecomeKey }
        if !others { NSApp.setActivationPolicy(.accessory) }
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "MacsPane"
    }

}
#endif
