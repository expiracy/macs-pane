import Foundation

/// A saved window "scene": a set of regions, each bound to an app, that the notch arranges in one
/// tap. The app-bound sibling of Smart Windows' MRU auto-tiler, where Smart Windows fills slots with
/// your most-recently-used windows, a layout pins specific apps to specific regions (and can still
/// leave a slot on `.mostRecent` as a filler). Pure value types so resolution stays unit-testable in
/// Core; the AppKit side resolves bundle ids and drives Accessibility.
///
/// Persistence is forward-compatible the same way every notch config is (CLAUDE.md Config rule): each
/// field decodes `decodeIfPresent ?? default`, and a malformed slot is dropped individually rather
/// than failing the whole decode, a throw here would reset `MacsPaneConfig` and wipe the user's settings.
public struct SnapLayout: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var slots: [SnapLayoutSlot]
    /// The editor's snapping grid for this layout, regions are cell blocks of this lattice. Persisted so
    /// the grid (and the cell-alignment of custom regions) stays stable across reopen.
    public var cols: Int
    public var rows: Int
    /// Draft profile choice, stored for future mode integration. It does not affect application.
    public var profileID: String?
    /// Empty layout whose boxes this preset fills; absent on scenes saved by older builds.
    public var layoutID: String?

    public init(id: String = UUID().uuidString, name: String, slots: [SnapLayoutSlot] = [],
                cols: Int = 3, rows: Int = 3, profileID: String? = nil, layoutID: String? = nil) {
        self.id = id
        self.name = name
        self.slots = slots
        self.cols = max(1, cols)
        self.rows = max(1, rows)
        self.profileID = profileID
        self.layoutID = layoutID
    }

    private enum CodingKeys: String, CodingKey { case id, name, slots, cols, rows, profileID, layoutID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Layout"
        self.cols = max(1, (try? c.decode(Int.self, forKey: .cols)) ?? 3)
        self.rows = max(1, (try? c.decode(Int.self, forKey: .rows)) ?? 3)
        self.profileID = try? c.decodeIfPresent(String.self, forKey: .profileID)
        self.layoutID = try? c.decodeIfPresent(String.self, forKey: .layoutID)
        // Drop malformed slots one at a time so a single bad entry can't empty the layout (or, via
        // MacsPaneConfig, reset every setting).
        self.slots = (try? c.decode([Failable<SnapLayoutSlot>].self, forKey: .slots))?
            .compactMap(\.value) ?? []
    }
}

/// One region of a layout and what fills it.
public struct SnapLayoutSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// The target region: a preset `WindowSnapZone`, or a user-drawn custom rectangle (`SnapRegion`).
    public var region: SnapRegion
    public var binding: SnapBinding
    /// For an `.app` binding: if the app isn't open when the layout is applied, launch it and then place
    /// it (vs the default, skip, letting a most-recent window fill the region). Ignored for other bindings.
    public var launchIfClosed: Bool
    /// A preset may leave a layout's box out entirely; keep it so the user can restore it.
    public var isRemoved: Bool
    /// The layer this box was drawn into (`WindowBoxLayers`). Nil for boxes saved before layers,
    /// those take the draw-order rule.
    public var layer: Int?

    public init(id: String = UUID().uuidString, region: SnapRegion, binding: SnapBinding,
                launchIfClosed: Bool = false, isRemoved: Bool = false, layer: Int? = nil) {
        self.id = id
        self.region = region
        self.binding = binding
        self.launchIfClosed = launchIfClosed
        self.isRemoved = isRemoved
        self.layer = layer
    }

    private enum CodingKeys: String, CodingKey { case id, region, binding, launchIfClosed, isRemoved, layer }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.region = (try? c.decode(SnapRegion.self, forKey: .region)) ?? .preset(.maximize)
        self.binding = (try? c.decode(SnapBinding.self, forKey: .binding)) ?? .mostRecent
        self.launchIfClosed = (try? c.decode(Bool.self, forKey: .launchIfClosed)) ?? false
        self.isRemoved = try c.decodeIfPresent(Bool.self, forKey: .isRemoved) ?? false
        self.layer = try? c.decodeIfPresent(Int.self, forKey: .layer)
    }
}

/// What fills a slot when a layout is applied.
public enum SnapBinding: Equatable, Sendable {
    /// A specific app, by bundle identifier, its top-ranked on-screen window is moved here.
    case app(bundleID: String)
    /// The next most-recently-used window not already placed (the Smart Windows behaviour, per slot).
    case mostRecent
    /// Leave the region unfilled.
    case empty
}

extension SnapBinding: Codable {
    private enum CodingKeys: String, CodingKey { case kind, bundleID }
    private enum Kind: String, Codable { case app, mostRecent, empty }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch (try? c.decode(Kind.self, forKey: .kind)) ?? .mostRecent {
        case .app:
            if let bundle = try? c.decode(String.self, forKey: .bundleID), !bundle.isEmpty {
                self = .app(bundleID: bundle)
            } else {
                self = .mostRecent   // an app binding with no bundle id is meaningless, degrade safely
            }
        case .mostRecent: self = .mostRecent
        case .empty: self = .empty
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let bundle):
            try c.encode(Kind.app, forKey: .kind)
            try c.encode(bundle, forKey: .bundleID)
        case .mostRecent: try c.encode(Kind.mostRecent, forKey: .kind)
        case .empty: try c.encode(Kind.empty, forKey: .kind)
        }
    }
}

/// Decodes `T` but swallows a per-element failure, so one malformed array entry doesn't fail the whole
/// array (and, through `MacsPaneConfig`, reset every setting). Used for a layout's slot list.
private struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
