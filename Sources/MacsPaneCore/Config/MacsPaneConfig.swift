import Foundation

/// Everything MacsPane saves. MacsPane is the Notch++ window manager on its own: the drag-to-top
/// snap picker, layouts and presets, run from the menu bar instead of the notch panel. It keeps one
/// file of its own (`MacsPanePaths.configURL`) and never writes Notch++'s `config.json`; the
/// value types are Notch++'s, so a preset made in either app means the same thing in the other.
///
/// Every field decodes `decodeIfPresent ?? default` (CLAUDE.md Config safety): an older or partial
/// file must never decode-fail, because a failed decode would reset every saved preset.
public struct MacsPaneConfig: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Dragging a window by its title bar to the top of the screen opens the snap picker in the notch.
    /// On by default here (it is opt-in in Notch++): snapping is what MacsPane is for.
    public var snap: WindowSnapConfig
    /// The user's own layouts and which layouts the drag-to-top picker offers.
    public var windows: WindowsConfig
    /// Saved presets: a layout whose boxes are bound to apps, applied in one click from the menu.
    public var presets: [SnapLayout]
    /// How long a dragged window must rest on the notch before the picker opens — Notch++'s
    /// `hoverExpandDelayMs` default, so the gesture feels the same in both apps.
    public var dwellMs: Int
    /// The first-time setup window was finished (or skipped). Absent in files written before setup
    /// existed, so those users see it once too.
    public var setupCompleted: Bool

    public init(schemaVersion: Int = MacsPaneConfig.currentSchemaVersion,
                snap: WindowSnapConfig = WindowSnapConfig(enabled: true),
                windows: WindowsConfig = WindowsConfig(),
                presets: [SnapLayout] = [],
                dwellMs: Int = 1000,
                setupCompleted: Bool = false) {
        self.schemaVersion = schemaVersion
        self.snap = snap
        self.windows = windows
        self.presets = presets
        self.dwellMs = dwellMs
        self.setupCompleted = setupCompleted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MacsPaneConfig()
        self.schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? d.schemaVersion
        self.snap = (try? c.decodeIfPresent(WindowSnapConfig.self, forKey: .snap)) ?? d.snap
        self.windows = (try? c.decodeIfPresent(WindowsConfig.self, forKey: .windows)) ?? d.windows
        self.presets = (try? c.decodeIfPresent([LossyDecoded<SnapLayout>].self, forKey: .presets))?
            .compactMap(\.value) ?? d.presets
        self.dwellMs = (try? c.decodeIfPresent(Int.self, forKey: .dwellMs)) ?? d.dwellMs
        self.setupCompleted = (try? c.decodeIfPresent(Bool.self, forKey: .setupCompleted)) ?? d.setupCompleted
    }

    public static let `default` = MacsPaneConfig()

    /// Default-value changes since the file was written, applied on load. Value-keyed, so running it
    /// every launch is harmless.
    public func migrated() -> MacsPaneConfig {
        var config = self
        config.windows.adoptFiveLayoutDefault()
        return config
    }

    /// The first-run seed when Notch++ is installed: its layouts, drag bar and presets carry over, and
    /// its snap tuning with them — but snapping is switched on, whatever Notch++ had, since a window
    /// manager that does not snap has nothing to do.
    public static func imported(from notch: NotchPlusPlusWindowSettings) -> MacsPaneConfig {
        var snap = notch.windowSnap
        snap.enabled = true
        return MacsPaneConfig(snap: snap, windows: notch.windows, presets: notch.snapLayouts,
                                dwellMs: notch.hoverExpandDelayMs)
    }

    /// "Import from Notch++" after the first run: adds the layouts and presets this file does not
    /// already hold (matched by id, so importing twice adds nothing) and leaves every setting alone.
    /// Returns how many were added.
    @discardableResult
    public mutating func merge(from notch: NotchPlusPlusWindowSettings) -> Int {
        let layoutIDs = Set(windows.layouts.map(\.id))
        let newLayouts = notch.windows.layouts.filter { !layoutIDs.contains($0.id) }
        let presetIDs = Set(presets.map(\.id))
        let newPresets = notch.snapLayouts.filter { !presetIDs.contains($0.id) }
        windows.layouts += newLayouts
        presets += newPresets
        return newLayouts.count + newPresets.count
    }

    /// Notch++'s window settings out of the bytes of its `config.json`, or nil when they cannot be read.
    public static func notchPlusPlusSettings(fromFile data: Data) -> NotchPlusPlusWindowSettings? {
        struct File: Decodable {
            struct Modules: Decodable { let notch: NotchPlusPlusWindowSettings }
            let modules: Modules
        }
        return (try? JSONDecoder().decode(File.self, from: data))?.modules.notch
    }
}

/// The part of Notch++'s `config.json` (`modules.notch`) that MacsPane imports: its snap tuning, its
/// layouts and drag bar, its presets and its rest-to-open delay. Every other key in that file is
/// ignored, and each of these falls back to MacsPane's default, so any Notch++ version's file reads.
public struct NotchPlusPlusWindowSettings: Decodable, Equatable, Sendable {
    public var windowSnap: WindowSnapConfig
    public var windows: WindowsConfig
    public var snapLayouts: [SnapLayout]
    public var hoverExpandDelayMs: Int

    public init(windowSnap: WindowSnapConfig = WindowSnapConfig(), windows: WindowsConfig = WindowsConfig(),
                snapLayouts: [SnapLayout] = [], hoverExpandDelayMs: Int = 1000) {
        self.windowSnap = windowSnap
        self.windows = windows
        self.snapLayouts = snapLayouts
        self.hoverExpandDelayMs = hoverExpandDelayMs
    }

    private enum CodingKeys: String, CodingKey { case windowSnap, windows, snapLayouts, hoverExpandDelayMs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotchPlusPlusWindowSettings()
        windowSnap = (try? c.decodeIfPresent(WindowSnapConfig.self, forKey: .windowSnap)) ?? d.windowSnap
        windows = (try? c.decodeIfPresent(WindowsConfig.self, forKey: .windows)) ?? d.windows
        snapLayouts = (try? c.decodeIfPresent([LossyDecoded<SnapLayout>].self, forKey: .snapLayouts))?
            .compactMap(\.value) ?? d.snapLayouts
        hoverExpandDelayMs = (try? c.decodeIfPresent(Int.self, forKey: .hoverExpandDelayMs)) ?? d.hoverExpandDelayMs
    }
}
