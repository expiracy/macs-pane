import Foundation

/// Everything MacsPane saves: the drag-to-top snap picker's settings, layouts and presets, in one file
/// of its own (`MacsPanePaths.configURL`).
///
/// Every field decodes `decodeIfPresent ?? default` (CLAUDE.md Config safety): an older or partial
/// file must never decode-fail, because a failed decode would reset every saved preset.
public struct MacsPaneConfig: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Dragging a window by its title bar to the top of the screen opens the snap picker in the notch.
    /// On by default: snapping is what MacsPane is for.
    public var snap: WindowSnapConfig
    /// The user's own layouts and which layouts the drag-to-top picker offers.
    public var windows: WindowsConfig
    /// Saved presets: a layout whose boxes are bound to apps, applied in one click from the menu.
    public var presets: [SnapLayout]
    /// How long a dragged window must rest on the notch before the picker opens.
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

    /// Drag a preset to another place in the menu's list.
    public mutating func movePreset(from source: Int, to destination: Int) {
        ListOrder.move(from: source, to: destination, in: &presets)
    }

    /// A preset deleted from the menu, with where it was, so Undo can put it back.
    public struct RemovedPreset: Equatable, Sendable {
        public let preset: SnapLayout
        public let index: Int
    }

    /// Delete a preset; nil when there is none with that id.
    public mutating func removePreset(_ id: String) -> RemovedPreset? {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return nil }
        return RemovedPreset(preset: presets.remove(at: index), index: index)
    }

    public mutating func restore(_ removed: RemovedPreset) {
        guard !presets.contains(where: { $0.id == removed.preset.id }) else { return }
        presets.insert(removed.preset, at: min(removed.index, presets.count))
    }

    /// Default-value changes since the file was written, applied on load. Value-keyed, so running it
    /// every launch is harmless.
    public func migrated() -> MacsPaneConfig {
        var config = self
        config.windows.adoptFiveLayoutDefault()
        return config
    }
}
