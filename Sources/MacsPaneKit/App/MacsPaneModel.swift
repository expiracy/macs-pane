#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// MacsPane's state and everything its menu and settings window can do: apply, save, rename and
/// delete presets and layouts, choose the drag bar's layouts, switch snapping.
/// Window moves go through `SmartWindowsViewModel` (presets) and the drag controller (snaps).
/// Main thread only.
final class MacsPaneModel: ObservableObject {
    /// The last time MacsPane moved your windows, with its Undo, for the notch's Undo activity.
    struct LastAction {
        let title: String
        let symbol: String
        let perform: WindowsUndo?
        /// The preset's layout with its apps, for the notch's Undo activity; nil draws `symbol`.
        var glyph: [SnapGlyphBox]?
        let date = Date()
    }

    @Published private(set) var config: MacsPaneConfig
    @Published private(set) var lastAction: LastAction?

    let notch: MacsPaneNotchController
    private let store: MacsPaneConfigStore
    private let recents: RecentWindowsService
    private let smart: SmartWindowsViewModel
    /// A preset was just applied: offer its Undo on screen.
    var onUndoPrompt: ((LastAction) -> Void)?
    /// Opens the box editor on a layout or preset to draw.
    var onEdit: ((WindowBoxDraft) -> Void)?
    /// Opens the first-time setup window again (the dropdown's Setup button).
    var onShowSetup: (() -> Void)?

    init(store: MacsPaneConfigStore) {
        self.store = store
        self.config = store.config
        let recents = RecentWindowsService()
        self.recents = recents
        self.notch = MacsPaneNotchController(config: store.config, recents: recents)
        self.smart = SmartWindowsViewModel(recents: recents, arranger: AXWindowArranger(),
                                           screenProvider: { MacsPaneModel.pointerScreen })
        smart.onArranged = { [weak self] undo, preset in
            guard let self else { return }
            // The notch has the preset's icons drawn already; resolving them again cost the Undo its start.
            let glyph = self.notch.host.windowSnap.presets.first { $0.id == preset.id }?.boxes
                ?? ResolvedPickerPreset(preset).boxes
            self.record(LastAction(title: "\(preset.name) applied", symbol: "square.grid.2x2",
                                   perform: undo, glyph: glyph))
            if let applied = self.lastAction { self.onUndoPrompt?(applied) }
        }
        notch.host.onPresetChosen = { [weak self] id, dragged in self?.applyPreset(id, dragged: dragged) }
        notch.host.onPairingTiled = { [weak self] undo in
            guard let self else { return }
            self.record(LastAction(title: "Windows tiled", symbol: "rectangle.split.2x1", perform: undo))
            if let tiled = self.lastAction { self.onUndoPrompt?(tiled) }
        }
        notch.onAuthorizationChange = { [weak self] in self?.objectWillChange.send() }
        store.onChange = { [weak self] config in
            self?.config = config
            self?.notch.apply(config)
        }
    }

    func start() {
        recents.start()
        notch.start()
    }

    func stop() {
        notch.stop()
        recents.stop()
    }

    // MARK: - State the menu reads

    var isAuthorized: Bool { notch.isAuthorized }

    // MARK: - Switches

    func setSnapping(_ on: Bool) {
        store.update { $0.snap.enabled = on }
        if on, !isAuthorized { requestAccess() }
    }

    func requestAccess() { notch.requestAuthorization() }

    /// Setup was finished or closed: it is not shown at launch again.
    func completeSetup() { store.update { $0.setupCompleted = true } }

    /// How long a dragged window rests on the notch before the picker opens, in milliseconds.
    func setDwell(_ ms: Int) { store.update { $0.dwellMs = ms } }

    /// Whether drawing a box lands its edges on the fine grid.
    func setDrawGrid(_ on: Bool) { store.update { $0.windows.drawGrid = on } }

    func toggleBar(_ layoutID: String) {
        store.update { $0.windows.toggleInBar(layoutID) }
    }

    /// A layout dragged to another place in the menu's list; the notch follows the same order.
    func moveLayout(from source: Int, to destination: Int) {
        store.update { $0.windows.moveLayout(from: source, to: destination) }
    }

    /// A preset dragged to another place in the menu's list.
    func movePreset(from source: Int, to destination: Int) {
        store.update { $0.movePreset(from: source, to: destination) }
    }

    // MARK: - Presets

    /// `dragged`: the window a notch drop carried to the top, which the preset's Undo sends home.
    func applyPreset(_ id: String, dragged: WindowUndoCapture.DraggedHome? = nil) {
        guard let preset = config.presets.first(where: { $0.id == id }) else { return }
        guard isAuthorized else { requestAccess(); return }
        smart.applyLayout(preset, dragged: dragged)
    }

    func renamePreset(_ id: String, to typed: String) {
        store.update { config in
            guard let index = config.presets.firstIndex(where: { $0.id == id }) else { return }
            config.presets[index].name = WindowDefaultName.resolve(
                typed, word: "Preset", taken: config.presets.filter { $0.id != id }.map(\.name))
        }
    }

    /// Delete a preset (the menu has already asked).
    func deletePreset(_ id: String) {
        store.update { _ = $0.removePreset(id) }
    }

    // MARK: - Layouts

    func renameLayout(_ id: String, to typed: String) {
        store.update { config in
            guard let index = config.windows.layouts.firstIndex(where: { $0.id == id }) else { return }
            config.windows.layouts[index].name = WindowDefaultName.resolve(
                typed, word: "Layout", taken: config.windows.layoutCatalog.filter { $0.id != id }.map(\.name))
        }
    }

    /// A deleted layout leaves the drag bar too; presets made from it keep their own boxes.
    /// Delete one of your layouts, out of the notch too (the menu has already asked).
    func deleteLayout(_ id: String) {
        store.update { _ = $0.windows.removeLayout(id) }
    }

    // MARK: - Drawing presets and layouts

    func newPreset() { onEdit?(WindowBoxDraft(kind: .preset)) }

    func newLayout() { onEdit?(WindowBoxDraft(kind: .layout)) }

    /// The menu row being named in place ("preset-…" or "layout-…"): one just saved from the desktop.
    private(set) var renaming: String?

    /// Save the windows on this screen as a preset straight away, each box bound to its app, under the
    /// next free name, which the menu then offers to change in place. With no windows to save it
    /// opens the editor on an empty preset instead.
    func newPresetFromDesktop() {
        guard let screen = Self.pointerScreen, let desktop = desktopPreset(on: screen) else { newPreset(); return }
        let preset = SnapLayout(name: WindowDefaultName.next("Preset", taken: config.presets.map(\.name)),
                                slots: desktop.slots)
        store.update { $0.presets.append(preset) }
        renaming = "preset-\(preset.id)"
    }

    /// Save a layout with a box where each window on this screen is, offered in the notch, under the
    /// next free name, which the menu then offers to change in place. With no windows it opens the
    /// editor on an empty layout instead.
    func newLayoutFromDesktop() {
        guard let screen = Self.pointerScreen, let desktop = desktopPreset(on: screen) else { newLayout(); return }
        var draft = WindowBoxDraft(kind: .layout)
        draft.replaceBoxes(with: desktop.slots.map(\.region))
        let layout = draft.layout(named: WindowDefaultName.next("Layout",
                                                                taken: config.windows.layoutCatalog.map(\.name)))
        store.update { config in
            config.windows.layouts.append(layout)
            if !config.windows.dragBarLayoutIDs.contains(layout.id) { config.windows.toggleInBar(layout.id) }
        }
        renaming = "layout-\(layout.id)"
    }

    /// The name typed for the row being named in place; nil keeps the name it was saved under.
    func finishRenaming(_ key: String, to typed: String?) {
        guard renaming == key else { return }
        renaming = nil
        guard let typed else { return }
        if key.hasPrefix("preset-") { renamePreset(String(key.dropFirst("preset-".count)), to: typed) }
        if key.hasPrefix("layout-") { renameLayout(String(key.dropFirst("layout-".count)), to: typed) }
    }

    func editPreset(_ id: String) {
        guard let preset = config.presets.first(where: { $0.id == id }) else { return }
        onEdit?(WindowBoxDraft(preset: preset))
    }

    func editLayout(_ id: String) {
        guard let layout = config.windows.layouts.first(where: { $0.id == id }) else { return }
        onEdit?(WindowBoxDraft(layout: layout))
    }

    /// The windows on `screen` as an unsaved preset: each one's box, bound to its app.
    func desktopPreset(on screen: NSScreen) -> SnapLayout? {
        WindowDesktopSnapshot.preset(of: rankedWindows(), named: "", visibleFrame: screen.visibleFrame,
                                     primaryHeight: WindowControlService.primaryHeight, bundleID: bundleID)
    }

    /// Save what the editor drew: a new layout or preset, or the one it was opened on. A layout is
    /// offered in the drag picker or not as `offeredInPicker` says.
    func save(_ draft: WindowBoxDraft, offeredInPicker: Bool = true) {
        guard draft.canSave else { return }
        switch draft.kind {
        case .layout: saveLayout(draft, offeredInPicker: offeredInPicker)
        case .preset: savePreset(draft)
        }
    }

    private func saveLayout(_ draft: WindowBoxDraft, offeredInPicker: Bool) {
        let taken = config.windows.layoutCatalog.filter { $0.id != draft.editingID }.map(\.name)
        let layout = draft.layout(named: WindowDefaultName.resolve(draft.name, word: "Layout", taken: taken))
        store.update { config in
            if let index = config.windows.layouts.firstIndex(where: { $0.id == layout.id }) {
                config.windows.layouts[index] = layout
            } else {
                config.windows.layouts.append(layout)
            }
            if offeredInPicker != config.windows.dragBarLayoutIDs.contains(layout.id) {
                config.windows.toggleInBar(layout.id)
            }
        }
    }

    private func savePreset(_ draft: WindowBoxDraft) {
        let taken = config.presets.filter { $0.id != draft.editingID }.map(\.name)
        let name = WindowDefaultName.resolve(draft.name, word: "Preset", taken: taken)
        store.update { config in
            if let index = config.presets.firstIndex(where: { $0.id == draft.editingID }) {
                config.presets[index].name = name
                config.presets[index].slots = draft.slots
            } else {
                config.presets.append(SnapLayout(name: name, slots: draft.slots))
            }
        }
    }

    // MARK: - Helpers

    /// "This screen" for a menu command: the one under the pointer, which is the one with the menu bar
    /// you just clicked.
    static var pointerScreen: NSScreen? { NSScreen.containing(NSEvent.mouseLocation) ?? NSScreen.main }

    private func rankedWindows() -> [ProcessWindowInfo] {
        let windows = recents.orderedRecentWindows(excludingPid: ProcessInfo.processInfo.processIdentifier)
        smart.visuals.cache(for: windows)
        return windows
    }

    private func bundleID(_ window: ProcessWindowInfo) -> String? {
        smart.visuals.bundleID(for: window.ownerPid)
            ?? NSRunningApplication(processIdentifier: window.ownerPid)?.bundleIdentifier
    }

    /// Run `action`'s Undo if it is still the last move, so an old activity can't undo a newer one.
    /// `done` runs once the windows are back (at once when there is nothing to undo).
    func perform(_ action: LastAction, done: @escaping () -> Void) {
        guard let current = lastAction, current.date == action.date, let perform = current.perform else {
            done()
            return
        }
        perform(done)
    }

    /// Undo runs once: it clears the last move, so a second click can't replay an old arrangement.
    private func record(_ action: LastAction) {
        guard let perform = action.perform else { lastAction = action; return }
        lastAction = LastAction(title: action.title, symbol: action.symbol, perform: { [weak self] done in
            self?.lastAction = nil
            perform(done)
        }, glyph: action.glyph)
    }
}
#endif
