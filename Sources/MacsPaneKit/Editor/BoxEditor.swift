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

    /// What a shortcut being recorded is for: one box of a layout, or the preset itself.
    enum ShortcutTarget: Equatable {
        case box(String)
        case preset
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
    /// The layers the toolbar's Layers menu has hidden (0 is the front). A view setting only: hidden
    /// boxes are still saved.
    @Published private(set) var hiddenLayers: Set<Int> = []
    /// The box whose layer number is being typed in its stepper, and what is typed so far.
    @Published var typingLayerFor: String?
    @Published var typedLayer = ""
    @Published private(set) var installedApps: [InstalledApp] = []
    /// The shortcut waiting for its keys, and a word on keys that can't be one.
    @Published private(set) var recordingShortcut: ShortcutTarget?
    @Published private(set) var shortcutHint: String?

    let app: MacsPaneModel
    let screen: NSScreen?
    var onClose: () -> Void = {}
    private let installedAppsProvider: InstalledAppsProviding
    /// Set once the drawing is saved, cancelled or deleted, so a second ⏎ can't save it twice.
    private var finished = false
    /// Takes every key while a shortcut is recording.
    private var keyMonitor: Any?

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

    // MARK: - Layers

    /// The boxes on screen now, in the order to paint them: those on hidden layers are left out.
    var shownBoxes: [WindowBoxDraft.Box] {
        draft.paintOrder.filter { WindowBoxLayers.isDrawn($0.layer, hidden: hiddenLayers) }
    }

    /// The boxes on one layer, in the order they were drawn.
    func boxes(onLayer layer: Int) -> [WindowBoxDraft.Box] { draft.boxes.filter { $0.layer == layer } }

    /// A box's number, as its badge shows it.
    func number(of box: WindowBoxDraft.Box) -> Int { (draft.boxes.firstIndex { $0.id == box.id } ?? 0) + 1 }

    func setLayer(_ layer: Int, shown: Bool) {
        if shown { hiddenLayers.remove(layer) } else { hiddenLayers.insert(layer) }
        // A box you can no longer see can't stay picked.
        if let selected = draft.selectedBox, hiddenLayers.contains(selected.layer) { select(nil) }
    }

    func showAllLayers() { hiddenLayers = [] }

    /// Move a box a layer back (+1) or forward (−1). Its new layer is shown, so it doesn't vanish
    /// under the pointer.
    func shiftLayer(_ id: String, by step: Int) {
        draft.shiftLayer(id, by: step)
        reveal(id)
    }

    /// Put a box on the layer typed for it (1 is the front).
    func setLayer(_ id: String, toNumber number: Int) {
        draft.setLayer(id, to: number - 1)
        reveal(id)
    }

    /// A box just drawn or moved is always on a layer you can see; layers left empty drop out of the
    /// hidden ones.
    func reveal(_ id: String) {
        guard let layer = draft.box(id)?.layer else { return }
        hiddenLayers.remove(layer)
        hiddenLayers = hiddenLayers.intersection(draft.layersInUse)
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

    // MARK: - Shortcuts

    func shortcut(for target: ShortcutTarget) -> KeyShortcut? {
        switch target {
        case .box(let id): return draft.box(id)?.shortcut
        case .preset: return draft.shortcut
        }
    }

    func setShortcut(_ shortcut: KeyShortcut?, for target: ShortcutTarget) {
        switch target {
        case .box(let id): draft.setShortcut(shortcut, forBox: id)
        case .preset: draft.shortcut = shortcut
        }
    }

    /// Where a shortcut comes from when this saves, if something else has it now: "Desk".
    func shortcutTakenFrom(_ target: ShortcutTarget) -> String? {
        guard let shortcut = shortcut(for: target), let owner = app.shortcutOwner(shortcut) else { return nil }
        switch (owner.action, draft.kind) {
        case (.preset(let id), .preset) where id == draft.editingID: return nil
        case (.layoutBox(let id, _), .layout) where id == draft.editingID: return nil
        default: return owner.name
        }
    }

    /// Wait for the keys of a shortcut: the next combo pressed is it, esc keeps the one it had, ⌫
    /// clears it. Shortcuts already in use don't run meanwhile, so they can be recorded.
    func recordShortcut(for target: ShortcutTarget) {
        guard recordingShortcut != target else { stopRecording(); return }
        stopRecording()
        if case .box(let id) = target { select(id) }
        recordingShortcut = target
        app.setShortcutsSuspended(true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let target = self.recordingShortcut else { return event }
            self.record(event, for: target)
            return nil
        }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if recordingShortcut != nil { app.setShortcutsSuspended(false) }
        recordingShortcut = nil
        shortcutHint = nil
    }

    private func record(_ event: NSEvent, for target: ShortcutTarget) {
        let shortcut = KeyShortcut(event: event)
        switch (shortcut.keyCode, shortcut.modifiers.isEmpty) {
        case (53, true):
            stopRecording()
        case (51, true), (117, true):
            setShortcut(nil, for: target)
            stopRecording()
        default:
            guard shortcut.isUsable else { shortcutHint = "Hold ⌘, ⌃ or ⌥ too"; return }
            setShortcut(shortcut, for: target)
            stopRecording()
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    // MARK: - Leaving

    func save() {
        guard draft.canSave, !finished else { return }
        finished = true
        stopRecording()
        app.save(draft, offeredInPicker: offeredInPicker)
        onClose()
    }

    func cancel() {
        finished = true
        stopRecording()
        onClose()
    }

    func delete() {
        guard let id = draft.editingID, !finished else { return }
        guard confirmingDelete else { confirmingDelete = true; return }
        finished = true
        stopRecording()
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

    /// ⌫ removes the selected box, unless you are typing a name. (A shortcut being recorded takes its
    /// keys before they get here.)
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
