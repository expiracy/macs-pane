import Testing
import CoreGraphics
@testable import MacsPaneCore

// A notched 14" laptop as the primary display plus externals placed to its right, its left (negative
// AppKit X) and above it (AppKit Y past the primary's height, so negative AX Y). Frames are AppKit
// bottom-left, as `NSScreen` reports them; each visible frame drops a 25-pt menu bar (the laptop's 38).
private struct Display {
    let frame: CGRect
    let visible: CGRect
    var geometry: NotchGeometry {
        NotchGeometry(screenFrame: frame, safeAreaTop: 0, leftAuxWidth: nil, rightAuxWidth: nil,
                      menubarHeight: frame.maxY - visible.maxY)
    }
}

private let laptop = Display(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                             visible: CGRect(x: 0, y: 0, width: 1512, height: 944))
private let right = Display(frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440),
                            visible: CGRect(x: 1512, y: -200, width: 2560, height: 1415))
private let left = Display(frame: CGRect(x: -1920, y: 100, width: 1920, height: 1080),
                           visible: CGRect(x: -1920, y: 100, width: 1920, height: 1055))
private let above = Display(frame: CGRect(x: -200, y: 982, width: 1920, height: 1080),
                            visible: CGRect(x: -200, y: 982, width: 1920, height: 1055))
private let externals = [right, left, above]
private let primaryHeight = laptop.frame.height

private func win(_ id: UInt32, pid: Int32 = 10, cgFrame: CGRect) -> ProcessWindowInfo {
    ProcessWindowInfo(id: id, ownerPid: pid, title: "w\(id)", frame: cgFrame, isOnScreen: true, layer: 0, alpha: 1)
}

private func close(_ a: CGRect, _ b: CGRect, within tolerance: CGFloat = 2) -> Bool {
    abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
        && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
}

// MARK: - The notch target on each display

@Test func notchTargetSitsAtTheTopCentreOfEveryExternal() {
    for display in externals {
        let geo = display.geometry
        let strip = geo.collapsedRect
        #expect(strip.midX == display.frame.midX)
        #expect(strip.maxY == display.frame.maxY)
        #expect(display.frame.contains(strip))
        #expect(!strip.intersects(laptop.frame))

        let zone = geo.windowSnapCollapsedZone(targetWidth: 400)
        #expect(zone.maxY == display.frame.maxY && zone.midX == display.frame.midX)
        #expect(display.frame.contains(zone))
    }
}

@Test func notchPanelStaysOnItsOwnDisplay() {
    for display in [laptop] + externals {
        let panel = display.geometry.windowFrame(contentSize: CGSize(width: 900, height: 260))
        #expect(display.frame.contains(panel))
    }
}

@Test func externalWithoutAMenuBarStillGetsAFullHeightTarget() {
    // "Displays have separate Spaces" off: a secondary screen has no menu bar of its own.
    let bare = NotchGeometry(screenFrame: right.frame, safeAreaTop: 0, leftAuxWidth: nil,
                             rightAuxWidth: nil, menubarHeight: 0)
    #expect(bare.collapsedSize.height == NotchGeometry.standardNotchSize.height)
    #expect(bare.collapsedRect.maxY == right.frame.maxY)
}

// MARK: - Snapping onto an external

@Test func snapZonesOnAnExternalLandInsideItInAXSpace() {
    for display in externals {
        let axVisible = AXCoordinateConverter.flipRect(display.visible, primaryHeight: primaryHeight)
        for zone in WindowSnapZone.allCases {
            let appKit = zone.frame(in: display.visible)
            #expect(display.visible.contains(appKit), "\(zone) left the display")
            let ax = AXCoordinateConverter.flipRect(appKit, primaryHeight: primaryHeight)
            #expect(axVisible.insetBy(dx: -0.5, dy: -0.5).contains(ax), "\(zone) left the display in AX space")
        }
    }
}

@Test func maximizeOnTheDisplayAboveStartsJustUnderItsMenuBar() {
    let ax = AXCoordinateConverter.flipRect(WindowSnapZone.maximize.frame(in: above.visible),
                                            primaryHeight: primaryHeight)
    let axTopOfAbove = primaryHeight - above.frame.maxY   // -1080
    #expect(ax.minY == axTopOfAbove + 25)
    #expect(ax.maxY == 0)                                 // its bottom meets the laptop's top
    #expect(ax.minX == above.frame.minX)
}

// MARK: - Presets on an external

@Test func savingOnAnExternalCapturesOnlyItsWindows() {
    let axAbove = AXCoordinateConverter.flipRect(above.frame, primaryHeight: primaryHeight)
    let axLeft = AXCoordinateConverter.flipRect(left.frame, primaryHeight: primaryHeight)
    let onAbove = win(1, cgFrame: CGRect(x: axAbove.minX + 100, y: axAbove.minY + 60, width: 900, height: 700))
    let onLeft = win(2, cgFrame: CGRect(x: axLeft.minX + 40, y: axLeft.minY + 40, width: 800, height: 600))
    let onLaptop = win(3, cgFrame: CGRect(x: 0, y: 38, width: 756, height: 944))
    let windows = [onAbove, onLeft, onLaptop]

    #expect(WindowDesktopSnapshot.captured(windows, visibleFrame: above.visible,
                                           primaryHeight: primaryHeight).map(\.id) == [1])
    #expect(WindowDesktopSnapshot.captured(windows, visibleFrame: left.visible,
                                           primaryHeight: primaryHeight).map(\.id) == [2])
    #expect(WindowDesktopSnapshot.captured(windows, visibleFrame: laptop.visible,
                                           primaryHeight: primaryHeight).map(\.id) == [3])
}

@Test func aPresetSavedOnAnExternalPutsWindowsBackWhereTheyWere() throws {
    for display in externals {
        let axVisible = AXCoordinateConverter.flipRect(display.visible, primaryHeight: primaryHeight)
        let a = win(1, pid: 1, cgFrame: CGRect(x: axVisible.minX, y: axVisible.minY,
                                              width: axVisible.width / 2, height: axVisible.height))
        let b = win(2, pid: 2, cgFrame: CGRect(x: axVisible.midX + 37, y: axVisible.minY + 120,
                                              width: 700, height: 500))
        let bundles: [Int32: String] = [1: "com.a", 2: "com.b"]
        let preset = try #require(WindowDesktopSnapshot.preset(
            of: [a, b], named: "P", visibleFrame: display.visible, primaryHeight: primaryHeight,
            bundleID: { bundles[$0.ownerPid] }))

        // Shuffle both windows onto the laptop, then apply the preset on the external again.
        let moved = [win(1, pid: 1, cgFrame: CGRect(x: 10, y: 50, width: 400, height: 300)),
                     win(2, pid: 2, cgFrame: CGRect(x: 500, y: 50, width: 400, height: 300))]
        let plan = SnapLayoutApplier.plan(for: preset, rankedWindows: moved,
                                          bundleID: { bundles[$0.ownerPid] }, visibleFrame: display.visible)
        let axFrames = Dictionary(uniqueKeysWithValues: plan.placements.map {
            ($0.window.id, AXCoordinateConverter.flipRect($0.frame, primaryHeight: primaryHeight))
        })
        #expect(close(try #require(axFrames[1]), a.frame))
        #expect(close(try #require(axFrames[2]), b.frame))
    }
}

@Test func aPresetSavedOnTheLaptopScalesOntoABiggerExternal() throws {
    let leftHalfOfLaptop = win(1, pid: 1, cgFrame: CGRect(x: 0, y: 38, width: 756, height: 944))
    let preset = try #require(WindowDesktopSnapshot.preset(
        of: [leftHalfOfLaptop], named: "P", visibleFrame: laptop.visible, primaryHeight: primaryHeight,
        bundleID: { _ in "com.a" }))
    let plan = SnapLayoutApplier.plan(for: preset, rankedWindows: [leftHalfOfLaptop],
                                      bundleID: { _ in "com.a" }, visibleFrame: right.visible)
    let placed = try #require(plan.placements.first).frame
    #expect(close(placed, WindowSnapZone.leftHalf.frame(in: right.visible)))
}

// MARK: - The window roster across displays

@Test func windowsOnAnyDisplayStayInTheRosterButParkedOnesDoNot() {
    let displays = ([laptop] + externals).map { AXCoordinateConverter.flipRect($0.frame, primaryHeight: primaryHeight) }
    let onLeft = CGRect(x: -1500, y: 200, width: 800, height: 600)
    let onAbove = CGRect(x: 300, y: -900, width: 800, height: 600)
    let straddling = CGRect(x: 1300, y: 300, width: 600, height: 400)   // laptop → right external
    let parked = CGRect(x: -30_000, y: -30_000, width: 800, height: 600)
    #expect(WindowScreenCoverage.intersectsAnyDisplay(onLeft, displays: displays))
    #expect(WindowScreenCoverage.intersectsAnyDisplay(onAbove, displays: displays))
    #expect(WindowScreenCoverage.intersectsAnyDisplay(straddling, displays: displays))
    #expect(!WindowScreenCoverage.intersectsAnyDisplay(parked, displays: displays))
}

@Test func pairingSuggestionsTileTheExternalTheDragIsOn() {
    let dragged = win(1, pid: 1, cgFrame: CGRect(x: 0, y: 0, width: 400, height: 300))
    let partner = win(2, pid: 2, cgFrame: CGRect(x: 0, y: 0, width: 400, height: 300))
    let pairings = DragPairingSuggester.suggestions(dragged: dragged, recents: [partner], visibleFrame: left.visible)
    for placement in pairings.flatMap(\.placements) {
        #expect(left.visible.contains(placement.frame))
    }
}
