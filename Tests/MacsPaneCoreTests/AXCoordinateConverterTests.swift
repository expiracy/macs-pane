import Testing
import CoreGraphics
@testable import MacsPaneCore

// Height of a typical notched MacBook primary display.
private let H: CGFloat = 982

@Test func flipPointInvertsYAboutPrimaryHeight() {
    #expect(AXCoordinateConverter.flipPoint(CGPoint(x: 0, y: 0), primaryHeight: H) == CGPoint(x: 0, y: H))
    #expect(AXCoordinateConverter.flipPoint(CGPoint(x: 0, y: H), primaryHeight: H) == CGPoint(x: 0, y: 0))
    #expect(AXCoordinateConverter.flipPoint(CGPoint(x: 42, y: 100), primaryHeight: H) == CGPoint(x: 42, y: 882))
}

@Test func flipPointIsInvolutive() {
    let p = CGPoint(x: 137, y: 311)
    let back = AXCoordinateConverter.flipPoint(AXCoordinateConverter.flipPoint(p, primaryHeight: H), primaryHeight: H)
    #expect(back == p)
}

@Test func flipRectFlipsTheTopEdgeAndKeepsSize() {
    // AppKit rect at the bottom-left of the primary → AX rect measured from the top.
    let appKit = CGRect(x: 0, y: 0, width: 100, height: 100)   // maxY = 100
    let ax = AXCoordinateConverter.flipRect(appKit, primaryHeight: H)
    #expect(ax == CGRect(x: 0, y: H - 100, width: 100, height: 100))   // (0, 882, 100, 100)
}

@Test func flipRectIsInvolutive() {
    let r = CGRect(x: 200, y: 150, width: 640, height: 480)
    let back = AXCoordinateConverter.flipRect(AXCoordinateConverter.flipRect(r, primaryHeight: H), primaryHeight: H)
    #expect(back == r)
}

@Test func flipRectOnMonitorAbovePrimaryGivesNegativeAXY() {
    // A display stacked above the primary lives at AppKit Y > primary height; its AX Y is negative
    // (above the global top-left origin). This is the multi-monitor case the flip must get right.
    let abovePrimary = CGRect(x: 0, y: 1000, width: 100, height: 100)  // maxY = 1100
    let ax = AXCoordinateConverter.flipRect(abovePrimary, primaryHeight: H)
    #expect(ax == CGRect(x: 0, y: H - 1100, width: 100, height: 100))  // (0, -118, 100, 100)
    #expect(ax.minY < 0)
}
