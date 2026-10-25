#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// The box editor: presets and layouts are drawn straight onto the screen they will be used on. The
/// screen dims, and you drag to draw a box, drag a box to move it and drag its edges to resize it. In
/// a preset each box also names the app that opens there. A floating toolbar names the drawing, copies
/// the boxes of a layout or of the windows on screen into it, and saves it. Opened from the menu-bar dropdown.
final class BoxEditorModel: ObservableObject {
    enum StartPoint {
        case empty
        case windows
        case layout(WindowLayout)
    }

    /// One app a preset box can hold.
    struct AppChoice: Identifiable, Equatable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    @Published var draft: WindowBoxDraft
    @Published var grid: Bool {
        didSet { if grid != oldValue { app.setDrawGrid(grid) } }
    }
    /// A layout's place in the drag picker, saved with it.
    @Published var offeredInPicker: Bool
    /// The pending Delete: the toolbar asks once more before it removes the saved item.
    @Published var confirmingDelete = false
    /// The box a drag is drawing right now, before it is let go (top-left unit space).
    @Published var drawing: CGRect?
    /// The box whose app picker is open.
    @Published var pickingAppFor: String?
    @Published private(set) var installedApps: [InstalledApp] = []

    let app: MacsPaneModel
    let screen: NSScreen?
    var onClose: () -> Void = {}
    private let installedAppsProvider: InstalledAppsProviding
    /// Set once the drawing is saved, cancelled or deleted, so a second ⏎ can't save it twice.
    private var finished = false

    init(draft: WindowBoxDraft, app: MacsPaneModel, screen: NSScreen?,
         installedAppsProvider: InstalledAppsProviding = LiveInstalledApps()) {
        self.draft = draft
        self.app = app
        self.screen = screen
        self.installedAppsProvider = installedAppsProvider
        self.grid = app.config.windows.drawGrid
        self.offeredInPicker = draft.editingID.map { app.config.windows.dragBarLayoutIDs.contains($0) } ?? true
    }

    // MARK: - Reading

    var noun: String { draft.kind == .preset ? "preset" : "layout" }
    var title: String { draft.isNew ? "New \(noun)" : "Edit \(noun)" }

    /// The name a blank name field saves as.
    var defaultName: String {
        switch draft.kind {
        case .preset:
            return WindowDefaultName.next("Preset", taken: app.config.presets.filter { $0.id != draft.editingID }.map(\.name))
        case .layout:
            return WindowDefaultName.next("Layout", taken: app.config.windows.layoutCatalog
                .filter { $0.id != draft.editingID }.map(\.name))
        }
    }

    /// The toolbar menu that fills the drawing from boxes that already exist. A preset starts from a
    /// layout and then gets its apps; a layout copies another layout's boxes to change them.
    var sourceMenuTitle: String { draft.kind == .preset ? "Start from layout" : "Copy from" }

    /// Layouts whose boxes can fill the drawing: the built-ins and the user's own.
    var startLayouts: [WindowLayout] {
        app.config.windows.layoutCatalog.filter { $0.id != draft.editingID }
    }

    // MARK: - Apps

    /// Apps with a window open now, by name, the likeliest things to put in a box.
    var runningApps: [AppChoice] {
        let own = ProcessInfo.processInfo.processIdentifier
        var seen: Set<String> = []
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != own }
            .compactMap { app -> AppChoice? in
                guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return AppChoice(bundleID: id, name: app.localizedName ?? AppIdentityCache.shared.name(forBundleID: id))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var appsNotRunning: [AppChoice] {
        InstalledAppCatalog.notRunning(installedApps, running: Set(runningApps.map(\.bundleID)))
            .map { AppChoice(bundleID: $0.bundleID, name: $0.name) }
    }

    /// Scan the Applications folders once, off the main thread.
    func loadInstalledApps() {
        guard installedApps.isEmpty else { return }
        let provider = installedAppsProvider
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let apps = provider.installedApps()
            DispatchQueue.main.async { self?.installedApps = apps }
        }
    }

    func appName(_ bundleID: String) -> String {
        installedApps.first { $0.bundleID == bundleID }?.name ?? AppIdentityCache.shared.name(forBundleID: bundleID)
    }

    func appIcon(_ bundleID: String) -> NSImage? { AppIdentityCache.shared.icon(forBundleID: bundleID) }

    /// Put an app (or "any recent window", or nothing) in a box. A named app opens on apply if it's closed.
    func bind(_ binding: SnapBinding, to boxID: String) {
        draft.bind(binding, to: boxID)
        if case .app = binding { draft.setLaunchIfClosed(true, for: boxID) }
        draft.selection = boxID
        pickingAppFor = nil
    }

    /// Any app on disk, picked in the system's open panel, for the one that isn't in /Applications.
    func chooseOtherApp(for boxID: String, above window: NSWindow?) {
        pickingAppFor = nil
        let panel = NSOpenPanel()
        panel.title = "Choose an app for this box"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let window { panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1) }
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        bind(.app(bundleID: bundleID), to: boxID)
    }

    // MARK: - Editing

    func select(_ id: String?) {
        draft.selection = id
        confirmingDelete = false
    }

    func removeSelected() { draft.removeSelected() }

    func start(from point: StartPoint) {
        switch point {
        case .empty:
            draft.replaceBoxes(with: [])
        case .layout(let layout):
            draft.replaceBoxes(with: layout.boxes)
        case .windows:
            guard let screen, let desktop = app.desktopPreset(on: screen) else {
                draft.replaceBoxes(with: [])
                return
            }
            draft.replaceBoxes(with: desktop.slots.map(\.region), bindings: desktop.slots.map(\.binding))
        }
    }

    // MARK: - Leaving

    func save() {
        guard draft.canSave, !finished else { return }
        finished = true
        app.save(draft, offeredInPicker: offeredInPicker)
        onClose()
    }

    func cancel() {
        finished = true
        onClose()
    }

    func delete() {
        guard let id = draft.editingID, !finished else { return }
        guard confirmingDelete else { confirmingDelete = true; return }
        finished = true
        switch draft.kind {
        case .preset: app.deletePreset(id)
        case .layout: app.deleteLayout(id)
        }
        onClose()
    }
}

/// Shows the editor over the screen under the pointer and puts the app you were in back in front
/// afterwards. One drawing at a time: opening another replaces the first.
final class BoxEditorController {
    private var panel: BoxEditorPanel?
    private var previousApp: NSRunningApplication?

    func show(_ draft: WindowBoxDraft, app: MacsPaneModel) {
        close(restoringFocus: false)
        guard let screen = MacsPaneModel.pointerScreen ?? NSScreen.main else { return }
        let model = BoxEditorModel(draft: draft, app: app, screen: screen)
        model.onClose = { [weak self] in self?.close(restoringFocus: true) }
        let panel = BoxEditorPanel(screen: screen, model: model)
        let view = BoxEditorView(model: model, screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        panel.contentView = NSHostingView(rootView: view)
        self.panel = panel
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.loadInstalledApps()
    }

    func close(restoringFocus: Bool) {
        panel?.orderOut(nil)
        panel = nil
        if restoringFocus { previousApp?.activate() }
        previousApp = nil
    }
}

/// The full-screen sheet the editor draws on: borderless, above the menu bar and the Dock, and able to
/// take the keyboard so the name field, ⏎, esc and ⌫ work.
final class BoxEditorPanel: NSPanel {
    private weak var model: BoxEditorModel?

    init(screen: NSScreen, model: BoxEditorModel) {
        self.model = model
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Cover the whole screen, menu bar included: the drawing's coordinates start at the screen's top
    /// edge, and AppKit would otherwise push a window down below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// ⌫ removes the selected box, unless you are typing a name.
    override func keyDown(with event: NSEvent) {
        let deleteKeys: Set<UInt16> = [51, 117]
        if deleteKeys.contains(event.keyCode), !(firstResponder is NSTextView), let model {
            model.removeSelected()
            return
        }
        super.keyDown(with: event)
    }
}
#endif
