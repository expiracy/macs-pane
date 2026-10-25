import Foundation

/// Persisted configuration for window snapping (drag a window toward the notch to snap it to a
/// region). Like `FileShelfConfig`, every field decodes with a default so an older `config.json`
/// loads cleanly. Disabled by default: it's opt-in *and* needs Accessibility permission, so it
/// stays inert until the user turns it on and grants access.
public struct WindowSnapConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Legacy per-zone region list. The in-notch picker now shows a fixed, symmetric family-tile row
    /// (`WindowSnapFamily.defaultRow`) you aim *inside*, rather than one tile per enabled zone, but the
    /// field is retained so an older `config.json` still decodes cleanly (no wipe) and to leave room for
    /// future per-zone/per-family customization.
    public var regions: [WindowSnapZoneEntry]
    /// Also draw a full-screen translucent ghost of the target frame (Magnet-style). When false,
    /// only the in-notch picker tile highlights.
    public var showFullScreenPreview: Bool
    /// Minimum pointer travel (pt) before snap mode arms, avoids reacting to a plain click.
    public var dragActivationDistance: Int
    /// Height (pt) of the title-bar band a mouse-down must land in to count as a window drag (vs.
    /// a content/text drag). A pragmatic heuristic for apps with custom chrome, kept generous because
    /// arming is harmless on its own (nothing snaps until the drag reaches the notch *and* dwells), so a
    /// taller band that also catches a unified-toolbar grab beats one so thin it misses real title-bar drags.
    public var titleBarBandHeight: Int

    /// The enabled rows of `regions`, in list order. Legacy (the family picker no longer consumes this);
    /// retained for config compatibility and exercised by `WindowSnapConfigTests`.
    public var enabledZones: [WindowSnapZone] { regions.filter(\.enabled).map(\.zone) }

    public init(enabled: Bool = false,
                regions: [WindowSnapZoneEntry] = WindowSnapZoneEntry.defaultRegions,
                showFullScreenPreview: Bool = true,
                dragActivationDistance: Int = 8,
                titleBarBandHeight: Int = 44) {
        self.enabled = enabled
        self.regions = regions
        self.showFullScreenPreview = showFullScreenPreview
        self.dragActivationDistance = dragActivationDistance
        self.titleBarBandHeight = titleBarBandHeight
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WindowSnapConfig()
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        self.regions = Self.decodeRegions(from: decoder)
        self.showFullScreenPreview = try c.decodeIfPresent(Bool.self, forKey: .showFullScreenPreview) ?? d.showFullScreenPreview
        self.dragActivationDistance = try c.decodeIfPresent(Int.self, forKey: .dragActivationDistance) ?? d.dragActivationDistance
        self.titleBarBandHeight = try c.decodeIfPresent(Int.self, forKey: .titleBarBandHeight) ?? d.titleBarBandHeight
    }

    // MARK: - Resilient region decoding / migration

    /// Pre-customisation `config.json` named a preset under `zoneSet`; current files store an ordered
    /// `regions` array. Both decode here without ever throwing, a throw would reset the whole config
    /// and wipe the user's other settings.
    private enum LegacyKeys: String, CodingKey { case zoneSet }

    /// Lenient row shape: decoding `zone` as a plain string lets an unknown/removed zone be *dropped*
    /// rather than throwing the whole array away.
    private struct StoredEntry: Decodable { let zone: String; let enabled: Bool }

    private static func decodeRegions(from decoder: Decoder) -> [WindowSnapZoneEntry] {
        // 1. Current shape: a `regions` array. Map through the catalog (dropping unknown zones), then
        //    append any zone the stored list didn't mention as disabled, so a config written by an
        //    older build automatically gains regions added in a newer one (present but off).
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let stored = try? c.decodeIfPresent([StoredEntry].self, forKey: .regions) {
            let mapped = stored.compactMap { s in
                WindowSnapZone(rawValue: s.zone).map { WindowSnapZoneEntry(zone: $0, enabled: s.enabled) }
            }
            return completed(mapped)
        }
        // 2. Legacy shape: a `zoneSet` preset string → the zones it used to enable, in its old picker
        //    order, preserving the user's prior choice through the rename; the rest disabled. An
        //    unknown/removed preset falls through to the fresh default below.
        if let lc = try? decoder.container(keyedBy: LegacyKeys.self),
           let raw = try? lc.decodeIfPresent(String.self, forKey: .zoneSet),
           let order = legacyZoneOrder(forZoneSet: raw) {
            return completed(order.map { WindowSnapZoneEntry(zone: $0, enabled: true) })
        }
        // 3. Neither present (or an unknown preset) → fresh default.
        return WindowSnapZoneEntry.defaultRegions
    }

    /// Normalise a partial region list to cover the whole catalog exactly once: keep the given order,
    /// drop duplicate zones, then append every unmentioned catalog zone as disabled.
    private static func completed(_ given: [WindowSnapZoneEntry]) -> [WindowSnapZoneEntry] {
        var seen = Set<WindowSnapZone>()
        var result = given.filter { seen.insert($0.zone).inserted }
        result.append(contentsOf: WindowSnapZone.allCases
            .filter { !seen.contains($0) }
            .map { WindowSnapZoneEntry(zone: $0, enabled: false) })
        return result
    }

    /// The zones a removed preset name used to offer, in its original picker order, or `nil` for an
    /// unknown/removed preset, which the caller treats as "fall back to the default region list".
    private static func legacyZoneOrder(forZoneSet raw: String) -> [WindowSnapZone]? {
        switch raw {
        case "halvesQuarters":
            return [.maximize, .leftHalf, .rightHalf,
                    .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
        case "full":
            return [.maximize, .leftHalf, .rightHalf,
                    .leftThird, .centerThird, .rightThird,
                    .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
        default:
            return nil
        }
    }
}
