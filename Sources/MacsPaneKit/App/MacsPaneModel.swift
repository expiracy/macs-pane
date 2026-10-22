#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// MacsPane's state and everything its menu and settings window can do: apply, save, rename and
/// delete presets and layouts, choose the drag bar's layouts, switch snapping, import from Notch++.
/// Window moves go through `SmartWindowsViewModel` (presets) and the drag controller (snaps).
/// Main thread only.
final class MacsPaneModel: ObservableObject {
    /// The last change MacsPane made, with its one follow-up (Undo, or Rename in Settings) — what the
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
    /// Opens the settings window on the Presets section (the Rename follow-up).
    var onShowSettings: (() -> Void)?
    /// Opens the first-time setup window again (Settings › Run setup again).
    var onShowSetup: (() -> Void)?

    private static let lastActionLifetime: TimeInterval = 15 * 60
    static let notchPlusPlusBundleID = "com.jgray.macplusplus"

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
                                   fact: moved == 1 ? "1 window" : "\(moved) windows",
                                   actionTitle: undo == nil ? nil : "Undo", perform: undo))
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

    /// Notch++ is running with its own drag-to-notch snapping on, so a drag would open two pickers.
    var notchPlusPlusAlsoSnaps: Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.notchPlusPlusBundleID).isEmpty
        else { return false }
        return notchPlusPlusConfig()?.windowSnap.enabled ?? false
    }

    var canImportFromNotchPlusPlus: Bool { notchPlusPlusConfig() != nil }

    // MARK: - Settings

    func setSnapping(_ on: Bool) {
        store.update { $0.snap.enabled = on }
        if on, !isAuthorized { requestAccess() }
    }

    func requestAccess() { notch.requestAuthorization() }

    /// Setup was finished or closed: it is not shown at launch again.
    func completeSetup() { store.update { $0.setupCompleted = true } }

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

    func savePresetFromDesktop() {
        guard let screen = Self.pointerScreen else { return }
        let windows = rankedWindows()
        let name = WindowDefaultName.next("Preset", taken: config.presets.map(\.name))
        guard let preset = WindowDesktopSnapshot.preset(
            of: windows, named: name, visibleFrame: screen.visibleFrame,
            primaryHeight: WindowControlService.primaryHeight, bundleID: bundleID)
        else {
            record(LastAction(title: "Nothing to save", symbol: "exclamationmark.circle",
                              fact: "no windows on this screen", actionTitle: nil, perform: nil))
            return
        }
        store.update { $0.presets.append(preset) }
        record(LastAction(title: "\(name) saved", symbol: "checkmark.circle",
                          fact: preset.slots.count == 1 ? "1 window" : "\(preset.slots.count) windows",
                          actionTitle: "Rename", perform: { [weak self] in self?.onShowSettings?() }))
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

    /// The windows on this screen become a layout's empty boxes, offered in the drag bar when it has room.
    func saveLayoutFromDesktop() {
        guard let screen = Self.pointerScreen else { return }
        let boxes = WindowDesktopSnapshot.boxes(of: rankedWindows(), visibleFrame: screen.visibleFrame,
                                                primaryHeight: WindowControlService.primaryHeight)
        guard !boxes.isEmpty else {
            record(LastAction(title: "Nothing to save", symbol: "exclamationmark.circle",
                              fact: "no windows on this screen", actionTitle: nil, perform: nil))
            return
        }
        let name = WindowDefaultName.next("Layout", taken: config.windows.layoutCatalog.map(\.name))
        var layout = WindowLayout(name: name, boxes: [])
        boxes.forEach { layout.appendBox($0) }
        var offered = false
        store.update { config in
            config.windows.layouts.append(layout)
            offered = WindowDragBarEditor.toggle(layout.id, in: &config.windows.dragBarLayoutIDs,
                                                 catalog: config.windows.layoutCatalog) == .offered
        }
        record(LastAction(title: "\(name) saved", symbol: "checkmark.circle",
                          fact: offered ? "in the drag bar" : "drag bar full",
                          actionTitle: "Rename", perform: { [weak self] in self?.onShowSettings?() }))
    }

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

    // MARK: - Notch++

    /// Adds Notch++'s layouts and presets that are not here yet; returns how many.
    @discardableResult
    func importFromNotchPlusPlus() -> Int {
        guard let notch = notchPlusPlusConfig() else { return 0 }
        var added = 0
        store.update { added = $0.merge(from: notch) }
        return added
    }

    static func notchPlusPlusSeed() -> MacsPaneConfig? {
        guard let url = MacsPanePaths.notchPlusPlusConfigURL(), let data = try? Data(contentsOf: url),
              let notch = MacsPaneConfig.notchPlusPlusSettings(fromFile: data) else { return nil }
        return .imported(from: notch)
    }

    private func notchPlusPlusConfig() -> NotchPlusPlusWindowSettings? {
        guard let url = MacsPanePaths.notchPlusPlusConfigURL(), let data = try? Data(contentsOf: url) else {
            return nil
        }
        return MacsPaneConfig.notchPlusPlusSettings(fromFile: data)
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
