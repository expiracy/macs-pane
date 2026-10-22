import Testing
import CoreGraphics
@testable import MacsPaneCore

// A visible frame with a non-zero origin, to catch zone math that assumes (0,0).
private let vf = CGRect(x: 100, y: 50, width: 1600, height: 1000)

@Test func maximizeFillsVisibleFrame() {
    #expect(WindowSnapZone.maximize.frame(in: vf) == vf)
}

@Test func halvesPartitionVisibleFrame() {
    let left = WindowSnapZone.leftHalf.frame(in: vf)
    let right = WindowSnapZone.rightHalf.frame(in: vf)
    #expect(left == CGRect(x: 100, y: 50, width: 800, height: 1000))
    #expect(right == CGRect(x: 900, y: 50, width: 800, height: 1000))
    // No overlap, exact tiling: they meet at the midline and cover the whole width.
    #expect(left.maxX == right.minX)
    #expect(left.width + right.width == vf.width)
}

@Test func quartersPartitionVisibleFrame() {
    // In AppKit bottom-left coords the TOP quarters have the higher Y (midY).
    #expect(WindowSnapZone.topLeftQuarter.frame(in: vf)     == CGRect(x: 100, y: 550, width: 800, height: 500))
    #expect(WindowSnapZone.topRightQuarter.frame(in: vf)    == CGRect(x: 900, y: 550, width: 800, height: 500))
    #expect(WindowSnapZone.bottomLeftQuarter.frame(in: vf)  == CGRect(x: 100, y: 50,  width: 800, height: 500))
    #expect(WindowSnapZone.bottomRightQuarter.frame(in: vf) == CGRect(x: 900, y: 50,  width: 800, height: 500))
}

@Test func thirdsTileVisibleFrameLeftToRight() {
    // Thirds are each width/3; abutments are compared with a sub-pixel tolerance because
    // `minX + 2·thirdW` and `maxX − thirdW` differ by a floating-point ULP (irrelevant on screen).
    func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
    let w = vf.width / 3
    let l = WindowSnapZone.leftThird.frame(in: vf)
    let c = WindowSnapZone.centerThird.frame(in: vf)
    let r = WindowSnapZone.rightThird.frame(in: vf)
    #expect(l.minX == vf.minX)
    #expect(close(l.maxX, c.minX))       // left meets center
    #expect(close(c.maxX, r.minX))       // center meets right
    #expect(close(r.maxX, vf.maxX))      // right meets the edge
    #expect(l.width == w)
    #expect(c.width == w)
    #expect(r.width == w)
    for z in [l, c, r] { #expect(z.height == vf.height) }
}

@Test func twoThirdsAreTwiceAThird() {
    let w = vf.width / 3
    #expect(WindowSnapZone.leftTwoThirds.frame(in: vf)  == CGRect(x: vf.minX,     y: vf.minY, width: 2 * w, height: vf.height))
    #expect(WindowSnapZone.rightTwoThirds.frame(in: vf) == CGRect(x: vf.minX + w, y: vf.minY, width: 2 * w, height: vf.height))
}

@Test func verticalHalvesPartitionVisibleFrame() {
    // Top/bottom halves are full-width; in AppKit bottom-left coords the TOP half has the higher Y.
    let top = WindowSnapZone.topHalf.frame(in: vf)
    let bottom = WindowSnapZone.bottomHalf.frame(in: vf)
    #expect(top    == CGRect(x: 100, y: 550, width: 1600, height: 500))
    #expect(bottom == CGRect(x: 100, y: 50,  width: 1600, height: 500))
    #expect(bottom.maxY == top.minY)                 // meet at the midline
    #expect(top.height + bottom.height == vf.height)  // exact tiling
}

@Test func horizontalThirdsTileVisibleFrameBottomToTop() {
    func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
    let h = vf.height / 3
    let b = WindowSnapZone.bottomThird.frame(in: vf)
    let m = WindowSnapZone.middleThird.frame(in: vf)
    let t = WindowSnapZone.topThird.frame(in: vf)
    #expect(b.minY == vf.minY)
    #expect(close(b.maxY, m.minY))       // bottom meets middle
    #expect(close(m.maxY, t.minY))       // middle meets top
    #expect(close(t.maxY, vf.maxY))      // top meets the edge
    for z in [b, m, t] {
        #expect(close(z.height, h))
        #expect(z.width == vf.width)     // full-width rows
        #expect(z.minX == vf.minX)
    }
}

@Test func horizontalTwoThirdsAreTwiceAThird() {
    let h = vf.height / 3
    #expect(WindowSnapZone.bottomTwoThirds.frame(in: vf) == CGRect(x: vf.minX, y: vf.minY,     width: vf.width, height: 2 * h))
    #expect(WindowSnapZone.topTwoThirds.frame(in: vf)    == CGRect(x: vf.minX, y: vf.minY + h, width: vf.width, height: 2 * h))
}

@Test func defaultRegionsCoverCatalogAndEnableSymmetricSet() {
    let regions = WindowSnapZoneEntry.defaultRegions
    // Covers every catalog zone exactly once (order is enabled-first, not pure catalog order).
    #expect(Set(regions.map(\.zone)) == Set(WindowSnapZone.allCases))
    #expect(regions.count == WindowSnapZone.allCases.count)
    #expect(Set(regions.map(\.zone)).count == regions.count)   // no dupes
    // Enabled, in picker order: left quarters · left half · maximize (centre) · right half · right quarters.
    #expect(regions.filter(\.enabled).map(\.zone) == [.topLeftQuarter, .bottomLeftQuarter,
                                                      .leftHalf, .maximize, .rightHalf,
                                                      .topRightQuarter, .bottomRightQuarter])
}
