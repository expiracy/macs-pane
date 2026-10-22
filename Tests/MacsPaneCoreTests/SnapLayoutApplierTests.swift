import Testing
import CoreGraphics
@testable import MacsPaneCore

private let vf = CGRect(x: 0, y: 0, width: 1600, height: 1000)

private func win(_ id: UInt32, pid: Int32 = 0) -> ProcessWindowInfo {
    ProcessWindowInfo(id: id, ownerPid: pid, title: nil,
                      frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                      isOnScreen: true, layer: 0, alpha: 1)
}

/// A bundle-id lookup backed by a window-id → bundle map — what the AppKit driver builds from
/// `NSRunningApplication`, faked here so the applier stays pure in tests.
private func bundles(_ map: [UInt32: String]) -> (ProcessWindowInfo) -> String? { { map[$0.id] } }

@Test func appSlotPlacesThatAppsWindow() {
    let layout = SnapLayout(name: "L", slots: [
        SnapLayoutSlot(region: .preset(.leftHalf), binding: .app(bundleID: "com.b")),
        SnapLayoutSlot(region: .preset(.rightHalf), binding: .app(bundleID: "com.a")),
    ])
    let p = SnapLayoutApplier.plan(for: layout, rankedWindows: [win(1), win(2)],
                                         bundleID: bundles([1: "com.a", 2: "com.b"]), visibleFrame: vf).placements
    #expect(p.map(\.window.id) == [2, 1])
    #expect(p[0].frame == WindowSnapZone.leftHalf.frame(in: vf))
    #expect(p[1].frame == WindowSnapZone.rightHalf.frame(in: vf))
}

@Test func mostRecentFillsInRankedOrder() {
    let layout = SnapLayout(name: "L", slots: [
        SnapLayoutSlot(region: .preset(.leftHalf), binding: .mostRecent),
        SnapLayoutSlot(region: .preset(.rightHalf), binding: .mostRecent),
    ])
    let p = SnapLayoutApplier.plan(for: layout, rankedWindows: [win(1), win(2)],
                                         bundleID: bundles([:]), visibleFrame: vf).placements
    #expect(p.map(\.window.id) == [1, 2])
}

@Test func emptySlotIsSkipped() {
    let layout = SnapLayout(name: "L", slots: [
        SnapLayoutSlot(region: .preset(.leftHalf), binding: .empty),
        SnapLayoutSlot(region: .preset(.rightHalf), binding: .mostRecent),
    ])
    let p = SnapLayoutApplier.plan(for: layout, rankedWindows: [win(1)],
                                         bundleID: bundles([:]), visibleFrame: vf).placements
    #expect(p.count == 1)
    #expect(p[0].window.id == 1)
    #expect(p[0].frame == WindowSnapZone.rightHalf.frame(in: vf))
}

@Test func appNotRunningAndNotLaunchingLeavesItEmpty() {
    let layout = SnapLayout(name: "L", slots: [
        SnapLayoutSlot(region: .preset(.leftHalf), binding: .app(bundleID: "com.missing")),
    ])
    let plan = SnapLayoutApplier.plan(for: layout, rankedWindows: [win(1)],
                                      bundleID: bundles([1: "com.a"]), visibleFrame: vf)
    #expect(plan.placements.isEmpty)        // missing app, not launching → blank (no random window)
    #expect(plan.launchPending.isEmpty)
}

@Test func noWindowIsPlacedTwice() {
    let layout = SnapLayout(name: "L", slots: [
        SnapLayoutSlot(region: .preset(.leftHalf), binding: .app(bundleID: "com.a")),
        SnapLayoutSlot(region: .preset(.rightHalf), binding: .mostRecent),
    ])
    let p = SnapLayoutApplier.plan(for: layout, rankedWindows: [win(1), win(2)],
                                         bundleID: bundles([1: "com.a", 2: "com.b"]), visibleFrame: vf).placements
    #expect(p.map(\.window.id) == [1, 2])   // mostRecent skips the already-used window 1
}

@Test func appPicksTopRankedWhenItHasMultipleWindows() {
    let layout = SnapLayout(name: "L", slots: [
        SnapLayoutSlot(region: .preset(.maximize), binding: .app(bundleID: "com.a")),
    ])
    let p = SnapLayoutApplier.plan(for: layout, rankedWindows: [win(1, pid: 7), win(2, pid: 7)],
                                         bundleID: bundles([1: "com.a", 2: "com.a"]), visibleFrame: vf).placements
    #expect(p.map(\.window.id) == [1])
}

@Test func runsOutOfWindowsGracefully() {
    let layout = SnapLayout(name: "L", slots: [
        SnapLayoutSlot(region: .preset(.leftHalf), binding: .mostRecent),
        SnapLayoutSlot(region: .preset(.rightHalf), binding: .mostRecent),
    ])
    let p = SnapLayoutApplier.plan(for: layout, rankedWindows: [win(1)],
                                         bundleID: bundles([:]), visibleFrame: vf).placements
    #expect(p.map(\.window.id) == [1])   // only one window → only the first slot fills
}

@Test func slotRegionsResolveToTheirFrames() {
    let layout = SnapLayout(name: "Quad", slots: [
        SnapLayoutSlot(region: .preset(.topLeftQuarter), binding: .mostRecent),
        SnapLayoutSlot(region: .preset(.bottomRightQuarter), binding: .mostRecent),
    ])
    let p = SnapLayoutApplier.plan(for: layout, rankedWindows: [win(1), win(2)],
                                         bundleID: bundles([:]), visibleFrame: vf).placements
    #expect(p[0].frame == WindowSnapZone.topLeftQuarter.frame(in: vf))
    #expect(p[1].frame == WindowSnapZone.bottomRightQuarter.frame(in: vf))
}

@Test func launchPendingWhenAppClosedAndLaunchEnabled() {
    let layout = SnapLayout(name: "L", slots: [
        SnapLayoutSlot(region: .preset(.leftHalf), binding: .app(bundleID: "com.missing"), launchIfClosed: true),
        SnapLayoutSlot(region: .preset(.rightHalf), binding: .mostRecent),
    ])
    let plan = SnapLayoutApplier.plan(for: layout, rankedWindows: [win(1)],
                                      bundleID: bundles([1: "com.a"]), visibleFrame: vf)
    // The launch slot must NOT burn the most-recent window: window 1 fills the mostRecent slot, and the
    // closed app is deferred to launch (carrying its region's frame).
    #expect(plan.placements.map(\.window.id) == [1])
    #expect(plan.placements.first?.frame == WindowSnapZone.rightHalf.frame(in: vf))
    #expect(plan.launchPending.map(\.bundleID) == ["com.missing"])
    #expect(plan.launchPending.first?.frame == WindowSnapZone.leftHalf.frame(in: vf))
}

/// A saved stack: two regions bound to the SAME app fan back to two DISTINCT windows of that app, in
/// slot order — so re-applying restores the overlapping windows rather than placing one window twice.
@Test func sameAppTwoRegionsGetDistinctWindows() {
    let layout = SnapLayout(name: "Stack", slots: [
        SnapLayoutSlot(region: .preset(.leftHalf), binding: .app(bundleID: "com.a")),
        SnapLayoutSlot(region: .preset(.rightHalf), binding: .app(bundleID: "com.a")),
    ])
    let plan = SnapLayoutApplier.plan(for: layout, rankedWindows: [win(1, pid: 7), win(2, pid: 7)],
                                      bundleID: bundles([1: "com.a", 2: "com.a"]), visibleFrame: vf)
    #expect(plan.placements.map(\.window.id) == [1, 2])
    #expect(plan.placements[0].frame == WindowSnapZone.leftHalf.frame(in: vf))
    #expect(plan.placements[1].frame == WindowSnapZone.rightHalf.frame(in: vf))
}
