import Testing
import Foundation
import CoreGraphics
@testable import MacsPaneCore

struct SnapRegionTests {
    private func approx(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test func presetRoundTrips() throws {
        let region = SnapRegion.preset(.leftHalf)
        let data = try JSONEncoder().encode(region)
        #expect(try JSONDecoder().decode(SnapRegion.self, from: data) == region)
    }

    @Test func customRoundTrips() throws {
        let region = SnapRegion.custom(NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5))
        let data = try JSONEncoder().encode(region)
        #expect(try JSONDecoder().decode(SnapRegion.self, from: data) == region)
    }

    /// A v1 layout persisted its region as a bare zone string; it must still decode, or `MacsPaneConfig`
    /// resets and the user loses every setting.
    @Test func legacyBareZoneDecodesToPreset() throws {
        let data = Data("\"leftHalf\"".utf8)
        #expect(try JSONDecoder().decode(SnapRegion.self, from: data) == .preset(.leftHalf))
    }

    @Test func legacySlotRegionDecodes() throws {
        let json = #"{"id":"s1","region":"rightHalf","binding":{"kind":"mostRecent"}}"#
        let slot = try JSONDecoder().decode(SnapLayoutSlot.self, from: Data(json.utf8))
        #expect(slot.region == .preset(.rightHalf))
    }

    @Test func customFrameMapsIntoVisibleFrame() {
        let region = SnapRegion.custom(NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
        let f = region.frame(in: CGRect(x: 100, y: 200, width: 1000, height: 800))
        #expect(approx(f.minX, 100) && approx(f.minY, 200))
        #expect(approx(f.width, 500) && approx(f.height, 800))
    }

    @Test func presetFrameMatchesZone() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(SnapRegion.preset(.rightHalf).frame(in: visible) == WindowSnapZone.rightHalf.frame(in: visible))
    }

    @Test func normalizedRectClampsToUnitSquare() {
        let r = NormalizedRect(x: -1, y: 2, width: 5, height: -3)
        #expect(r.x >= 0 && r.y >= 0)
        #expect(r.x + r.width <= 1.000001 && r.y + r.height <= 1.000001)
        #expect(r.width > 0 && r.height > 0)
    }

    @Test func normalizedRectIntersection() {
        let left = NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        let right = NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)        // edge-adjacent
        let overlapping = NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 1)
        #expect(!left.intersects(right))        // sharing only a boundary is not an overlap
        #expect(left.intersects(overlapping))
        #expect(left.intersects(left))
    }
}
