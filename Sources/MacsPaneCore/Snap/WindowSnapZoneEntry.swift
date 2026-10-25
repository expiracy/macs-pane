import Foundation

/// One row in the customisable Window Snap region list: a `WindowSnapZone` paired with whether it
/// shows in the in-notch picker. The ordered `[WindowSnapZoneEntry]` in `WindowSnapConfig.regions`
/// is the single source of truth for both *which* regions the picker offers and *what order* they
/// appear in, the notch consumes `WindowSnapConfig.enabledZones` (the enabled rows, in list order).
/// `id` is the zone itself, so a zone appears at most once and `ForEach`/`onMove` reorder cleanly.
public struct WindowSnapZoneEntry: Codable, Equatable, Sendable, Identifiable {
    public var zone: WindowSnapZone
    public var enabled: Bool
    public var id: WindowSnapZone { zone }

    public init(zone: WindowSnapZone, enabled: Bool) {
        self.zone = zone
        self.enabled = enabled
    }
}

public extension WindowSnapZoneEntry {
    /// The regions switched on, and the left-to-right order they take in the picker, on a fresh
    /// install: full-screen (maximize) dead-centre, the left/right halves flanking it, and the four
    /// quarters on the outer edges. A symmetric, sensible default row. Every *other* catalog zone
    /// (top/bottom halves, thirds, two-thirds) ships present-but-disabled, one toggle away in Settings.
    static let defaultEnabledOrder: [WindowSnapZone] = [
        .topLeftQuarter, .bottomLeftQuarter,
        .leftHalf,
        .maximize,
        .rightHalf,
        .topRightQuarter, .bottomRightQuarter,
    ]

    /// The full region list a fresh install starts with: the `defaultEnabledOrder` regions (enabled,
    /// in that order) followed by every remaining catalog zone disabled (in catalog order). Also the
    /// target of the Settings "Reset to default" button.
    static let defaultRegions: [WindowSnapZoneEntry] = {
        let enabledSet = Set(defaultEnabledOrder)
        let enabled = defaultEnabledOrder.map { WindowSnapZoneEntry(zone: $0, enabled: true) }
        let disabled = WindowSnapZone.allCases
            .filter { !enabledSet.contains($0) }
            .map { WindowSnapZoneEntry(zone: $0, enabled: false) }
        return enabled + disabled
    }()
}
