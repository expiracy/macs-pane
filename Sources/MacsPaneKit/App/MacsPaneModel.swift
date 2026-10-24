#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// MacsPane's state and everything its menu and settings window can do: apply, save, rename and
/// delete presets and layouts, choose the drag bar's layouts, switch snapping.
/// Window moves go through `SmartWindowsViewModel` (presets) and the drag controller (snaps).
/// Main thread only.
final class MacsPaneModel: ObservableObject {
    /// The last change MacsPane made, with its one follow-up (Undo, Apply or Edit), what the
    /// dropdown's box shows. It lapses after `lastActionLifetime`.
    struct LastAction {
        let title: String
        let symbol: String
        let fact: String
        let actionTitle: String?
        let perform: (() -> Void)?
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

    private static let lastActionLifetime: TimeInterval = 15 * 60

    init(store: MacsPaneConfigStore) {
        self.store = store
        self.config = store.config
        let recents = RecentWindowsService()
        self.recents = recents
        self.notch = MacsPaneNotchController(config: store.config, recents: recents)
        self.smart = SmartWindowsViewModel(recents: recents, arranger: AXWindowArranger(),
                                           screenProvider: { MacsPaneModel.pointerScreen })
        smart.onArranged = { [weak self] undo, _, _, moved in
            guard let self, let name = self.applyingName else { return }
            self.applyingName = nil
            self.record(LastAction(title: "\(name) applied", symbol: "square.grid.2x2",
                                   fact: moved == 1 ? "1 window moved" : "\(moved) windows moved",
                                   actionTitle: undo == nil ? nil : "Undo", perform: undo))
            // The same Undo, offered on screen straight away rather than only inside the menu.
            if undo != nil, let applied = self.lastAction { self.onUndoPrompt?(applied) }
        }
        notch.host.onPairingTiled = { [weak self] undo in
            self?.record(LastAction(title: "Windows tiled", symbol: "rectangle.split.2x1",
                                    fact: "from the notch", actionTitle: "Undo", perform: undo))
        }
        notch.onAuthorizationChange = { [weak self] in self?.objectWillChange.send() }
        store.onChange = { [weak self] config in
            self?.config = config
            self?.notch.apply(config)
        }
    }

    private var applyingName: String?

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
    var currentLastAction: LastAction? {
        guard let lastAction, Date().timeIntervalSince(lastAction.date) < Self.lastActionLifetime else { return nil }
        return lastAction
    }

    // MARK: - Switches

    func setSnapping(_ on: Bool) {
        store.update { $0.snap.enabled = on }
        if on, !isAuthorized { requestAccess() }
    }

    func requestAccess() { notch.requestAuthorization() }

    /// Setup was finished or closed: it is not shown at launch again.
    func completeSetup() { store.update { $0.setupCompleted = true } }

    /// Whether drawing a box lands its edges on the fine grid.
    func setDrawGrid(_ on: Bool) { store.update { $0.windows.drawGrid = on } }

    func toggleBar(_ layoutID: String) {
        store.update { config in
            _ = WindowDragBarEditor.toggle(layoutID, in: &config.windows.dragBarLayoutIDs,
                                           catalog: config.windows.layoutCatalog)
        }
    }

    // MARK: - Presets

    func applyPreset(_ id: String) {
        guard let preset = config.presets.first(where: { $0.id == id }) else { return }
        guard isAuthorized else { requestAccess(); return }
        applyingName = preset.name
        smart.applyLayout(preset)
        applyingName = nil   // nothing to place: no record
    }

    func renamePreset(_ id: String, to typed: String) {
        store.update { config in
            guard let index = config.presets.firstIndex(where: { $0.id == id }) else { return }
            config.presets[index].name = WindowDefaultName.resolve(
                typed, word: "Preset", taken: config.presets.filter { $0.id != id }.map(\.name))
        }
    }

    func deletePreset(_ id: String) {
        store.update { $0.presets.removeAll { $0.id == id } }
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
    func deleteLayout(_ id: String) {
        store.update { config in
            config.windows.layouts.removeAll { $0.id == id }
            WindowDragBarEditor.remove(id, from: &config.windows.dragBarLayoutIDs)
        }
    }

    // MARK: - Drawing presets and layouts

    /// A new preset, filled from the windows on this screen when there are any, else empty.
    func newPreset() {
        var draft = WindowBoxDraft(kind: .preset)
        if let screen = Self.pointerScreen, let desktop = desktopPreset(on: screen) {
            draft.replaceBoxes(with: desktop.slots.map(\.region), bindings: desktop.slots.map(\.binding))
        }
        onEdit?(draft)
    }

    func newLayout() { onEdit?(WindowBoxDraft(kind: .layout)) }

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
                _ = WindowDragBarEditor.toggle(layout.id, in: &config.windows.dragBarLayoutIDs,
                                               catalog: config.windows.layoutCatalog)
            }
        }
        record(LastAction(title: "\(layout.name) saved", symbol: "checkmark.circle",
                          fact: offeredInPicker ? "in the drag picker" : "not in the picker",
                          actionTitle: "Edit", perform: { [weak self] in self?.editLayout(layout.id) }))
    }

    private func savePreset(_ draft: WindowBoxDraft) {
        let taken = config.presets.filter { $0.id != draft.editingID }.map(\.name)
        let name = WindowDefaultName.resolve(draft.name, word: "Preset", taken: taken)
        var saved: SnapLayout?
        store.update { config in
            if let index = config.presets.firstIndex(where: { $0.id == draft.editingID }) {
                config.presets[index].name = name
                config.presets[index].slots = draft.slots
                saved = config.presets[index]
            } else {
                let preset = SnapLayout(name: name, slots: draft.slots)
                config.presets.append(preset)
                saved = preset
            }
        }
        guard let saved else { return }
        let apps = saved.slots.filter { $0.binding != .empty }.count
        record(LastAction(title: "\(name) saved", symbol: "checkmark.circle",
                          fact: apps == 1 ? "1 window" : "\(apps) windows",
                          actionTitle: "Apply", perform: { [weak self] in self?.applyPreset(saved.id) }))
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

    /// Run `action`'s follow-up if it is still the last change, so an Undo used from the menu can't run
    /// a second time from the on-screen prompt, or the other way round.
    func perform(_ action: LastAction) {
        guard let current = lastAction, current.date == action.date else { return }
        current.perform?()
    }

    /// Undo runs once: the box empties after it, so a second click can't replay an old arrangement.
    private func record(_ action: LastAction) {
        guard let perform = action.perform else { lastAction = action; return }
        lastAction = LastAction(title: action.title, symbol: action.symbol, fact: action.fact,
                                actionTitle: action.actionTitle, perform: { [weak self] in
            self?.lastAction = nil
            perform()
        })
    }
}
#endif
