import Testing
import Foundation
import CoreGraphics
@testable import MacsPaneCore

private func win(_ id: UInt32, pid: Int32, onScreen: Bool = true,
                 frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
                 layer: Int = 0, alpha: Double = 1) -> ProcessWindowInfo {
    ProcessWindowInfo(id: id, ownerPid: pid, title: "w\(id)", frame: frame,
                      isOnScreen: onScreen, layer: layer, alpha: alpha)
}

private let t0 = Date(timeIntervalSince1970: 1000)

@Test func ordersMostRecentlyFocusedWindowFirst() {
    let windows = [win(1, pid: 10), win(2, pid: 20), win(3, pid: 30)]
    let byWindow: [UInt32: Date] = [1: t0, 2: t0.addingTimeInterval(50), 3: t0.addingTimeInterval(20)]
    let ranked = RecentWindowRanker.ranked(windows: windows, recencyByWindow: byWindow,
                                           recencyByApp: [:], excludingPid: 99)
    #expect(ranked.map(\.id) == [2, 3, 1])
}

@Test func fallsBackToAppRecencyWhenWindowHasNone() {
    // 5 has no per-window time but its app just activated; 4 has an older per-window time.
    let windows = [win(4, pid: 10), win(5, pid: 20)]
    let ranked = RecentWindowRanker.ranked(windows: windows,
                                           recencyByWindow: [4: t0],
                                           recencyByApp: [20: t0.addingTimeInterval(100)],
                                           excludingPid: 99)
    #expect(ranked.map(\.id) == [5, 4])
}

@Test func neverFocusedKeepsStableFrontToBackOrder() {
    let windows = [win(7, pid: 1), win(8, pid: 2), win(9, pid: 3)]
    let ranked = RecentWindowRanker.ranked(windows: windows, recencyByWindow: [:],
                                           recencyByApp: [:], excludingPid: 0)
    #expect(ranked.map(\.id) == [7, 8, 9])
}

@Test func dropsOwnPidOffscreenAndJunkWindows() {
    let windows = [
        win(1, pid: 10),                                                      // keep
        win(2, pid: 99),                                                      // drop: our own app
        win(3, pid: 10, onScreen: false),                                     // drop: minimized / other Space
        win(4, pid: 10, frame: CGRect(x: 0, y: 0, width: 40, height: 40)),    // drop: too small (chrome debris)
        win(5, pid: 10, frame: CGRect(x: 0, y: 0, width: 1600, height: 30)),  // drop: Chromium chrome strip
        win(6, pid: 10, layer: 25),                                           // drop: non-standard layer
        win(7, pid: 10, alpha: 0),                                            // drop: invisible
    ]
    let ranked = RecentWindowRanker.ranked(windows: windows, recencyByWindow: [:],
                                           recencyByApp: [:], excludingPid: 99)
    #expect(ranked.map(\.id) == [1])
}

@Test func placementsPairSelectedWindowsWithSlotFrames() {
    let vf = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let selected = [win(1, pid: 10), win(2, pid: 20), win(3, pid: 30)]
    let placements = SmartWindowsLayout.placements(for: selected, in: vf)
    #expect(placements.map(\.window.id) == [1, 2, 3])
    #expect(placements.map(\.frame) == SmartWindowsLayout.frames(for: 3, in: vf))
    // Slot 1 (most recent) gets the big left half.
    #expect(placements[0].frame == CGRect(x: 0, y: 0, width: 800, height: 1000))
}

@Test func dropsOffScreenWindows() {
    // Off-screen windows (minimized, or living on another desktop) aren't offered — Smart Windows tiles
    // the current desktop only.
    let windows = [win(1, pid: 10), win(2, pid: 20, onScreen: false)]
    let ranked = RecentWindowRanker.ranked(windows: windows, recencyByWindow: [:],
                                           recencyByApp: [:], excludingPid: 99)
    #expect(ranked.map(\.id) == [1])
}

@Test func dropsJunkAndOwnPid() {
    let windows = [
        win(1, pid: 10),
        win(2, pid: 99),                                                      // drop: our own app
        win(3, pid: 10, frame: CGRect(x: 0, y: 0, width: 40, height: 40)),    // drop: chrome debris
    ]
    let ranked = RecentWindowRanker.ranked(windows: windows, recencyByWindow: [:],
                                           recencyByApp: [:], excludingPid: 99)
    #expect(ranked.map(\.id) == [1])
}
