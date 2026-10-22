import Testing
import CoreGraphics
@testable import MacsPaneCore

// A 1000-pt-tall primary display whose visible frame skips a 25-pt menu bar; window frames are CG
// top-left global, as CGWindowListCopyWindowInfo reports them.
private let primaryHeight: CGFloat = 1000
private let visible = CGRect(x: 0, y: 0, width: 1600, height: 975)

private func win(_ id: UInt32, pid: Int32 = 10, frame: CGRect) -> ProcessWindowInfo {
    ProcessWindowInfo(id: id, ownerPid: pid, title: "w\(id)", frame: frame,
                      isOnScreen: true, layer: 0, alpha: 1)
}

@Test func unitFrameNormalisesAndFlips() {
    // CG y=25 (just under the menu bar), 800×600 → AppKit y = 1000-25-600 = 375.
    let unit = SnapLayoutSnapshotter.unitFrame(for: win(1, frame: CGRect(x: 400, y: 25, width: 800, height: 600)),
                                               visibleFrame: visible, primaryHeight: primaryHeight)
    #expect(unit != nil)
    #expect(abs(unit!.minX - 0.25) < 0.001)
    #expect(abs(unit!.minY - 375.0 / 975.0) < 0.001)
    #expect(abs(unit!.width - 0.5) < 0.001)
    #expect(abs(unit!.height - 600.0 / 975.0) < 0.001)
}

@Test func unitFrameNilForDegenerateVisibleFrame() {
    let unit = SnapLayoutSnapshotter.unitFrame(for: win(1, frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
                                               visibleFrame: .zero, primaryHeight: primaryHeight)
    #expect(unit == nil)
}

@Test func snapshotBindsOneRegionPerWindowToItsApp() {
    let windows = [win(1, pid: 10, frame: CGRect(x: 0, y: 25, width: 800, height: 950)),
                   win(2, pid: 10, frame: CGRect(x: 800, y: 25, width: 800, height: 950))]
    let layout = SnapLayoutSnapshotter.snapshot(of: windows, named: "Two up",
                                                visibleFrame: visible, primaryHeight: primaryHeight,
                                                bundleID: { _ in "com.example.app" })
    #expect(layout?.name == "Two up")
    #expect(layout?.slots.count == 2)   // one region per WINDOW, same app twice
    #expect(layout?.slots.allSatisfy { $0.binding == .app(bundleID: "com.example.app") } == true)
}

@Test func snapshotSkipsWindowsWithoutBundleIDAndHonoursLaunchToggle() {
    let windows = [win(1, pid: 10, frame: CGRect(x: 0, y: 25, width: 800, height: 950)),
                   win(2, pid: 20, frame: CGRect(x: 800, y: 25, width: 800, height: 950))]
    let layout = SnapLayoutSnapshotter.snapshot(of: windows, named: "One",
                                                visibleFrame: visible, primaryHeight: primaryHeight,
                                                bundleID: { $0.ownerPid == 10 ? "com.example.app" : nil },
                                                launch: { _ in false })
    #expect(layout?.slots.count == 1)
    #expect(layout?.slots.first?.launchIfClosed == false)
}

@Test func snapshotNilWhenNoWindowQualifies() {
    let layout = SnapLayoutSnapshotter.snapshot(of: [win(1, frame: CGRect(x: 0, y: 0, width: 800, height: 600))],
                                                named: "Empty", visibleFrame: visible,
                                                primaryHeight: primaryHeight, bundleID: { _ in nil })
    #expect(layout == nil)
}
