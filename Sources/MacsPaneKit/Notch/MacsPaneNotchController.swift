#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// Puts MacsPane's drag-only notch on screen and runs the window-drag tracker against it. The
/// panel is click-through and sized once for the widest picker (both pairing tiles, wing budgeted on
/// both sides) so it never resizes mid-drag; it follows the drag to whichever screen the window is on,
/// and is re-placed when the displays change.
final class MacsPaneNotchController {
    let host: MacsPaneSnapHost
    private let snap: WindowSnapController
    private var panel: NotchPanel?
    private var screen: NSScreen?
    private var screenObserver: NSObjectProtocol?

    var isAuthorized: Bool { snap.isAuthorized }
    /// Accessibility was just granted (the controller polls for it while snapping is on).
    var onAuthorizationChange: (() -> Void)? {
        get { snap.onAuthorizationChange }
        set { snap.onAuthorizationChange = newValue }
    }

    init(config: MacsPaneConfig, recents: RecentWindowsService) {
        host = MacsPaneSnapHost(config: config, recents: recents)
        snap = WindowSnapController(host: host, config: config.snap)
        snap.followPointer = { [weak self] point in self?.follow(point) }
    }

    func start() {
        place(on: NSScreen.notchHost)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let current = self.screen.flatMap { old in NSScreen.screens.first { $0.displayID == old.displayID } }
            self.place(on: current ?? NSScreen.notchHost)
        }
        snap.activate()
    }

    func stop() {
        snap.deactivate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
    }

    func apply(_ config: MacsPaneConfig) {
        host.apply(config)
        snap.updateConfig(config.snap)
    }

    func requestAuthorization() { snap.requestAuthorization() }

    /// A drag emits no mouse-moved events, so the drag itself brings the resting notch to its screen.
    private func follow(_ point: CGPoint) {
        guard !host.isSnapPickerOpen, let target = NSScreen.containing(point), target !== screen else { return }
        place(on: target)
    }

    private func place(on screen: NSScreen?) {
        guard let screen else { return }
        let geometry = screen.notchGeometry
        host.notchSize = geometry.collapsedSize
        host.screenWidth = geometry.screenFrame.width
        host.hasRealNotch = geometry.hasRealNotch
        let widest = host.layout(suggestions: MacsPaneSnapHost.maxSuggestions)
        let content = CGSize(width: widest.pickerSize.width + widest.wingWidth, height: widest.pickerSize.height)
        let frame = geometry.windowFrame(contentSize: content)
        let panel = panel ?? makePanel(frame: frame)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.screen = screen
        snap.updateNotchGeometry(screen: screen, panelFrame: frame)
    }

    private func makePanel(frame: CGRect) -> NotchPanel {
        let panel = NotchPanel(contentRect: frame)
        panel.ignoresMouseEvents = true   // display only: the drag belongs to the window's own app
        let hosting = NSHostingView(rootView: MacsPaneNotchView(host: host))
        hosting.sizingOptions = []        // the panel keeps the frame placed here, not SwiftUI's ideal size
        panel.contentView = hosting
        self.panel = panel
        return panel
    }
}
#endif
