import Testing
import CoreGraphics
@testable import MacsPaneCore

private func name(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> String {
    SnapBoxName.describe(CGRect(x: x, y: y, width: w, height: h))
}

@Test func columnsAreNamedBySideAndSize() {
    #expect(name(0, 0, 0.5, 1) == "Left half")
    #expect(name(0.5, 0, 0.5, 1) == "Right half")
    #expect(name(0, 0, 2.0 / 3, 1) == "Left two thirds")
    #expect(name(1.0 / 3, 0, 1.0 / 3, 1) == "Middle third")
}

@Test func rowsAndCornersAreNamedTopToBottom() {
    // AppKit unit rects: y counts up from the bottom.
    #expect(name(0, 0.5, 1, 0.5) == "Top half")
    #expect(name(0, 0.5, 0.5, 0.5) == "Top left quarter")
    #expect(name(0.5, 0, 0.5, 0.5) == "Bottom right quarter")
}

@Test func otherShapesFallBackToWhereTheySit() {
    #expect(name(0, 0, 1, 1) == "Full screen")
    #expect(name(0.25, 0.04, 0.5, 0.92) == "Centre")
    #expect(name(0, 0, 0.6, 1) == "Left side")
    #expect(name(0.6, 0.5, 0.4, 0.5) == "Top right")
}
