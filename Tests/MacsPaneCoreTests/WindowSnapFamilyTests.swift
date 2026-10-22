import Testing
import CoreGraphics
@testable import MacsPaneCore

private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
private func close(_ a: CGRect, _ b: CGRect) -> Bool {
    close(a.minX, b.minX) && close(a.minY, b.minY) && close(a.width, b.width) && close(a.height, b.height)
}

@Test func defaultRowIsSymmetricWithMaximizeCentred() {
    let row = WindowSnapFamily.defaultRow
    #expect(row.count == 5)
    #expect(row[2] == .maximize)                       // dead centre
    #expect(row.first == .columnThirds && row.last == .rowThirds)   // thirds bookend
    #expect(row[1] == .quarters && row[3] == .halves)              // flank the centre
}

@Test func cellsUseTopLeftConvention() {
    // Top-left unit space: (0,0) top-left, the flip of the bottom-left frame(in:).
    #expect(close(WindowSnapFamily.halves.cell(for: .leftHalf),  CGRect(x: 0,   y: 0,   width: 0.5,     height: 1)))
    #expect(close(WindowSnapFamily.halves.cell(for: .rightHalf), CGRect(x: 0.5, y: 0,   width: 0.5,     height: 1)))
    #expect(close(WindowSnapFamily.quarters.cell(for: .topLeftQuarter),     CGRect(x: 0,   y: 0,   width: 0.5, height: 0.5)))
    #expect(close(WindowSnapFamily.quarters.cell(for: .bottomRightQuarter), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
    #expect(close(WindowSnapFamily.columnThirds.cell(for: .leftThird),  CGRect(x: 0,       y: 0, width: 1.0 / 3, height: 1)))
    #expect(close(WindowSnapFamily.columnThirds.cell(for: .rightThird), CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)))
    #expect(close(WindowSnapFamily.rowThirds.cell(for: .topThird),    CGRect(x: 0, y: 0,       width: 1, height: 1.0 / 3)))
    #expect(close(WindowSnapFamily.rowThirds.cell(for: .bottomThird), CGRect(x: 0, y: 2.0 / 3, width: 1, height: 1.0 / 3)))
    #expect(close(WindowSnapFamily.maximize.cell(for: .maximize), CGRect(x: 0, y: 0, width: 1, height: 1)))
}

@Test func aimResolvesQuartersByCorner() {
    let q = WindowSnapFamily.quarters
    #expect(q.zone(atNormalized: CGPoint(x: 0.25, y: 0.25)) == .topLeftQuarter)
    #expect(q.zone(atNormalized: CGPoint(x: 0.75, y: 0.25)) == .topRightQuarter)
    #expect(q.zone(atNormalized: CGPoint(x: 0.25, y: 0.75)) == .bottomLeftQuarter)
    #expect(q.zone(atNormalized: CGPoint(x: 0.75, y: 0.75)) == .bottomRightQuarter)
}

@Test func aimResolvesHalvesAndThirds() {
    #expect(WindowSnapFamily.halves.zone(atNormalized: CGPoint(x: 0.2, y: 0.5)) == .leftHalf)
    #expect(WindowSnapFamily.halves.zone(atNormalized: CGPoint(x: 0.8, y: 0.5)) == .rightHalf)
    let cols = WindowSnapFamily.columnThirds
    #expect(cols.zone(atNormalized: CGPoint(x: 0.1, y: 0.5)) == .leftThird)
    #expect(cols.zone(atNormalized: CGPoint(x: 0.5, y: 0.5)) == .centerThird)
    #expect(cols.zone(atNormalized: CGPoint(x: 0.9, y: 0.5)) == .rightThird)
    let rows = WindowSnapFamily.rowThirds
    #expect(rows.zone(atNormalized: CGPoint(x: 0.5, y: 0.1)) == .topThird)
    #expect(rows.zone(atNormalized: CGPoint(x: 0.5, y: 0.5)) == .middleThird)
    #expect(rows.zone(atNormalized: CGPoint(x: 0.5, y: 0.9)) == .bottomThird)
}

@Test func aimAlwaysResolvesMaximize() {
    for p in [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)] {
        #expect(WindowSnapFamily.maximize.zone(atNormalized: p) == .maximize)
    }
}

@Test func aimClampsOutOfBoundsToTheNearestEdgeCell() {
    // A pointer mapped just past the tile edge still resolves (clamped), never falls through.
    #expect(WindowSnapFamily.halves.zone(atNormalized: CGPoint(x: -0.5, y: 0.5)) == .leftHalf)
    #expect(WindowSnapFamily.halves.zone(atNormalized: CGPoint(x: 1.5, y: 0.5))  == .rightHalf)
    #expect(WindowSnapFamily.quarters.zone(atNormalized: CGPoint(x: 2, y: 2)) == .bottomRightQuarter)
}

@Test func memberCellsTileTheUnitBox() {
    // Each family's cells exactly cover the unit area with no overlap (area sums to 1).
    for family in WindowSnapFamily.allCases {
        let area = family.members.reduce(CGFloat.zero) { $0 + family.cell(for: $1).width * family.cell(for: $1).height }
        #expect(close(area, 1))
    }
}

@Test func seamsMatchTheSubdivision() {
    #expect(WindowSnapFamily.maximize.verticalSeams.isEmpty && WindowSnapFamily.maximize.horizontalSeams.isEmpty)
    #expect(WindowSnapFamily.halves.verticalSeams.count == 1 && close(WindowSnapFamily.halves.verticalSeams[0], 0.5))
    #expect(WindowSnapFamily.halves.horizontalSeams.isEmpty)
    #expect(WindowSnapFamily.quarters.verticalSeams.count == 1 && WindowSnapFamily.quarters.horizontalSeams.count == 1)
    let cols = WindowSnapFamily.columnThirds
    #expect(cols.verticalSeams.count == 2 && close(cols.verticalSeams[0], 1.0 / 3) && close(cols.verticalSeams[1], 2.0 / 3))
    #expect(cols.horizontalSeams.isEmpty)
    let rows = WindowSnapFamily.rowThirds
    #expect(rows.horizontalSeams.count == 2 && close(rows.horizontalSeams[0], 1.0 / 3) && close(rows.horizontalSeams[1], 2.0 / 3))
    #expect(rows.verticalSeams.isEmpty)
}

@Test func familyContainingRoundTripsItsMembers() {
    for family in WindowSnapFamily.allCases {
        for zone in family.members {
            #expect(WindowSnapFamily.family(containing: zone) == family)
        }
    }
    // A zone that belongs to no picker family (overlapping / two-thirds) resolves to nil.
    #expect(WindowSnapFamily.family(containing: .leftTwoThirds) == nil)
    #expect(WindowSnapFamily.family(containing: .topHalf) == nil)
}
