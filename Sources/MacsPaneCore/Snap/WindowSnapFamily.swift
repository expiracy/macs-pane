import CoreGraphics

/// A *family* of related snap zones presented as a single picker tile. Instead of one skinny tile per
/// zone (which makes the picker run wide once thirds/quarters are all enabled), each family folds its
/// zones into one tile the user aims *inside*, a corner for a quarter, a column for a third. The row
/// is then a short, fixed, symmetric set whatever the zone count.
///
/// A family's `members` *partition* the screen, they tile it with no overlap, so a point inside the
/// tile maps to exactly one zone, which is what makes aim-inside well-defined. (Overlapping zones,
/// top/bottom halves vs left/right, the two-thirds, don't tile and so aren't part of any family.)
///
/// Pure geometry, derived from `WindowSnapZone.frame(in:)`, so a tile's cells and the snap it performs
/// can never disagree, the same single-source-of-truth discipline `ZoneGlyph` already follows. Lives
/// in Core, unit-tested.
public enum WindowSnapFamily: String, CaseIterable, Codable, Sendable, Identifiable {
    case columnThirds
    case quarters
    case maximize
    case halves
    case rowThirds

    public var id: String { rawValue }

    /// The member zones, in a stable order. Each family's members tile the screen exactly once.
    public var members: [WindowSnapZone] {
        switch self {
        case .columnThirds: return [.leftThird, .centerThird, .rightThird]
        case .quarters:     return [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter]
        case .maximize:     return [.maximize]
        case .halves:       return [.leftHalf, .rightHalf]
        case .rowThirds:    return [.topThird, .middleThird, .bottomThird]
        }
    }

    /// The tile's label in the picker. Both thirds orientations read "Thirds", the seam direction
    /// (columns vs rows) and the resolved zone name ("Left third" vs "Top third") tell them apart.
    public var displayName: String {
        switch self {
        case .columnThirds, .rowThirds: return "Thirds"
        case .quarters:                 return "Quarters"
        case .maximize:                 return "Maximize"
        case .halves:                   return "Halves"
        }
    }

    /// The picker's fixed row, in on-screen left-to-right order: Maximize dead-centre, quarters and
    /// halves flanking it, the two thirds orientations bookending: a symmetric, uniform set.
    public static let defaultRow: [WindowSnapFamily] = [.columnThirds, .quarters, .maximize, .halves, .rowThirds]

    // MARK: - Geometry (top-left unit space, the picker's convention)

    /// A member zone's cell within a *top-left* unit box: `(0,0)` top-left … `(1,1)` bottom-right.
    /// Derived from `WindowSnapZone.frame(in:)` (AppKit bottom-left) with Y flipped, so a tile cell
    /// lines up exactly with the on-screen region it snaps to.
    public func cell(for zone: WindowSnapZone) -> CGRect {
        let r = zone.frame(in: CGRect(x: 0, y: 0, width: 1, height: 1))   // bottom-left
        return CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }

    /// The zone a normalized point inside the tile selects, the point in the same top-left unit space
    /// as `cell(for:)`. Inclusive on cell edges (a point on a seam resolves to the first member) and
    /// clamped, so an edge point never falls through.
    public func zone(atNormalized point: CGPoint) -> WindowSnapZone {
        let p = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        return members.first { z in
            let c = cell(for: z)
            return p.x >= c.minX && p.x <= c.maxX && p.y >= c.minY && p.y <= c.maxY
        } ?? members[0]
    }

    /// Internal vertical divider positions (x in 0…1), derived from the member cells so the drawn
    /// seams and the hit-test can't drift apart. Empty for `maximize`.
    public var verticalSeams: [CGFloat] { internalEdges(members.flatMap { [cell(for: $0).minX, cell(for: $0).maxX] }) }

    /// Internal horizontal divider positions (y in 0…1), same derivation as `verticalSeams`.
    public var horizontalSeams: [CGFloat] { internalEdges(members.flatMap { [cell(for: $0).minY, cell(for: $0).maxY] }) }

    /// Distinct interior edge positions from a list of cell edges: drop the 0/1 outer edges and
    /// de-duplicate (abutting cells share an edge), rounded so floating thirds collapse to one value.
    private func internalEdges(_ edges: [CGFloat]) -> [CGFloat] {
        var seen = Set<Int>()
        return edges
            .filter { $0 > 0.0001 && $0 < 0.9999 }
            .sorted()
            .filter { seen.insert(Int(($0 * 1000).rounded())).inserted }
    }

    /// The family whose members include `zone`, if any, used to light the right tile from the live
    /// `highlightedZone`.
    public static func family(containing zone: WindowSnapZone) -> WindowSnapFamily? {
        allCases.first { $0.members.contains(zone) }
    }
}
