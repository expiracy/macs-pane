import CoreGraphics

/// A rectangle in normalized screen space: origin bottom-left, every component in 0…1 of the screen's
/// visible frame — the same coordinate convention as `WindowSnapZone.frame(in:)`. Used for user-drawn
/// custom regions. Values are clamped into the unit square (keeping a usable sliver) so a malformed
/// rect can never push a window off-screen.
public struct NormalizedRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        let w = min(max(width, 0.01), 1)
        let h = min(max(height, 0.01), 1)
        self.width = w
        self.height = h
        self.x = min(max(x, 0), 1 - w)
        self.y = min(max(y, 0), 1 - h)
    }

    /// Map into a screen's visible frame (AppKit bottom-left).
    public func frame(in v: CGRect) -> CGRect {
        CGRect(x: v.minX + x * v.width,
               y: v.minY + y * v.height,
               width: width * v.width,
               height: height * v.height)
    }

    /// Whether two normalized rects overlap. Edge-adjacent rects (sharing only a boundary) do NOT count,
    /// so neighbouring cell regions don't evict each other in the editor.
    public func intersects(_ other: NormalizedRect) -> Bool {
        x < other.x + other.width && other.x < x + width &&
        y < other.y + other.height && other.y < y + height
    }
}

extension NormalizedRect: Codable {
    private enum CodingKeys: String, CodingKey { case x, y, width, height }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: (try? c.decode(Double.self, forKey: .x)) ?? 0,
                  y: (try? c.decode(Double.self, forKey: .y)) ?? 0,
                  width: (try? c.decode(Double.self, forKey: .width)) ?? 1,
                  height: (try? c.decode(Double.self, forKey: .height)) ?? 1)
    }
}

/// A layout slot's target region: a preset zone from the `WindowSnapZone` catalog, or a user-drawn
/// custom rectangle. Both resolve to a frame the same way, so the applier and previews treat them alike.
public enum SnapRegion: Equatable, Sendable {
    case preset(WindowSnapZone)
    case custom(NormalizedRect)

    public func frame(in visible: CGRect) -> CGRect {
        switch self {
        case .preset(let zone): return zone.frame(in: visible)
        case .custom(let rect): return rect.frame(in: visible)
        }
    }

    /// The normalized (unit-square, bottom-left) rect — handy for previews and the grid editor.
    public var unitRect: CGRect { frame(in: CGRect(x: 0, y: 0, width: 1, height: 1)) }

    /// The region as a `NormalizedRect` — for the editor's overlap (evict) test.
    public var normalized: NormalizedRect {
        let r = unitRect
        return NormalizedRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
    }

    public var displayName: String {
        switch self {
        case .preset(let zone): return zone.displayName
        case .custom: return "Custom"
        }
    }
}

extension SnapRegion: Codable {
    private enum CodingKeys: String, CodingKey { case kind, zone, rect }
    private enum Kind: String, Codable { case preset, custom }

    public init(from decoder: Decoder) throws {
        // New form: a keyed object { kind, zone | rect }.
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let kind = try? c.decode(Kind.self, forKey: .kind) {
            switch kind {
            case .preset:
                self = .preset((try? c.decode(WindowSnapZone.self, forKey: .zone)) ?? .maximize)
            case .custom:
                self = .custom((try? c.decode(NormalizedRect.self, forKey: .rect))
                                ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1))
            }
            return
        }
        // Legacy v1 form: the region was persisted as a bare `WindowSnapZone` raw string. Decoding it
        // still must succeed — a throw here would reset `MacsPaneConfig` and wipe every saved setting.
        if let zone = try? decoder.singleValueContainer().decode(WindowSnapZone.self) {
            self = .preset(zone)
            return
        }
        self = .preset(.maximize)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .preset(let zone):
            try c.encode(Kind.preset, forKey: .kind)
            try c.encode(zone, forKey: .zone)
        case .custom(let rect):
            try c.encode(Kind.custom, forKey: .kind)
            try c.encode(rect, forKey: .rect)
        }
    }
}
