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

private let leftHalf = CGRect(x: 0, y: 25, width: 800, height: 975)
private let rightHalf = CGRect(x: 800, y: 25, width: 800, height: 975)

@Test func desktopCaptureDropsTinyOffScreenAndStackedWindows() {
    let windows = [win(1, frame: leftHalf),
                   win(2, frame: leftHalf),                                    // same frame: one box
                   win(3, frame: CGRect(x: 0, y: 25, width: 20, height: 20)),  // too small
                   win(4, frame: CGRect(x: 5000, y: 25, width: 800, height: 600)),   // another screen
                   win(5, frame: rightHalf)]
    let kept = WindowDesktopSnapshot.captured(windows, visibleFrame: visible, primaryHeight: primaryHeight)
    #expect(kept.map(\.id) == [1, 5])
}

@Test func desktopBoxesAreTheCapturedFramesClampedToTheScreen() {
    let hanging = CGRect(x: 1200, y: 25, width: 800, height: 975)   // half of it past the right edge
    let boxes = WindowDesktopSnapshot.boxes(of: [win(1, frame: leftHalf), win(2, frame: hanging)],
                                            visibleFrame: visible, primaryHeight: primaryHeight)
    #expect(boxes.count == 2)
    #expect(boxes[0].unitRect == CGRect(x: 0, y: 0, width: 0.5, height: 1))
    #expect(boxes[1].unitRect == CGRect(x: 0.75, y: 0, width: 0.25, height: 1))
}

@Test func desktopPresetBindsEachBoxToItsAppAndLayersOverlaps() {
    let inner = CGRect(x: 200, y: 200, width: 400, height: 400)   // sits on top of the left half
    let preset = WindowDesktopSnapshot.preset(
        of: [win(1, pid: 10, frame: inner), win(2, pid: 20, frame: leftHalf), win(3, pid: 30, frame: rightHalf)],
        named: "", visibleFrame: visible, primaryHeight: primaryHeight,
        bundleID: { ["10": "com.a", "20": "com.b", "30": "com.c"]["\($0.ownerPid)"] })
    #expect(preset?.slots.map(\.binding) == [.app(bundleID: "com.a"), .app(bundleID: "com.b"),
                                             .app(bundleID: "com.c")])
    let layers = preset?.slots.compactMap(\.layer) ?? []
    #expect(layers.count == 3)
    #expect(layers[0] != layers[1])   // overlapping boxes land on different layers
}

@Test func desktopPresetIsNilWhenNothingQualifies() {
    let preset = WindowDesktopSnapshot.preset(
        of: [win(1, frame: CGRect(x: 0, y: 25, width: 10, height: 10))],
        named: "", visibleFrame: visible, primaryHeight: primaryHeight, bundleID: { _ in "com.a" })
    #expect(preset == nil)
}
