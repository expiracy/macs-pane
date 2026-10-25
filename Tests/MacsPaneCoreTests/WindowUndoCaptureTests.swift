import Testing
import CoreGraphics
@testable import MacsPaneCore

private let primaryHeight: CGFloat = 1000

private func win(_ id: UInt32, _ frame: CGRect) -> ProcessWindowInfo {
    ProcessWindowInfo(id: id, ownerPid: Int32(id), title: nil, frame: frame,
                      isOnScreen: true, layer: 0, alpha: 1)
}

private func appKit(_ cg: CGRect) -> CGRect { AXCoordinateConverter.flipRect(cg, primaryHeight: primaryHeight) }

@Test func undoReturnsEachWindowToItsFrameJustBeforeTheMove() {
    let stale = win(1, CGRect(x: 0, y: 0, width: 100, height: 100))
    let live = win(1, CGRect(x: 40, y: 60, width: 500, height: 400))
    let prior = WindowUndoCapture.priorPlacements(of: [stale], roster: [live], dragged: nil,
                                                  primaryHeight: primaryHeight)
    #expect(prior.map(\.frame) == [appKit(live.frame)])
}

@Test func undoReturnsTheDraggedWindowHomeNotWhereTheDragLeftIt() {
    let dropped = win(1, CGRect(x: 600, y: 0, width: 500, height: 400))
    let home = CGRect(x: 80, y: 300, width: 500, height: 400)
    let prior = WindowUndoCapture.priorPlacements(of: [dropped], roster: [dropped],
                                                  dragged: .init(windowID: 1, frame: home),
                                                  primaryHeight: primaryHeight)
    #expect(prior.map(\.frame) == [appKit(home)])
}

@Test func undoBringsTheDraggedWindowHomeEvenWhenThePresetLeftItOut() {
    let dropped = win(1, CGRect(x: 600, y: 0, width: 500, height: 400))
    let other = win(2, CGRect(x: 0, y: 200, width: 300, height: 300))
    let home = CGRect(x: 80, y: 300, width: 500, height: 400)
    let prior = WindowUndoCapture.priorPlacements(of: [other], roster: [dropped, other],
                                                  dragged: .init(windowID: 1, frame: home),
                                                  primaryHeight: primaryHeight)
    #expect(prior.map(\.window.id) == [1, 2])
    #expect(prior.first?.frame == appKit(home))
}

@Test func undoListsWindowsFrontToBackAsTheyWereStacked() {
    let front = win(3, CGRect(x: 0, y: 0, width: 300, height: 300))
    let middle = win(1, CGRect(x: 50, y: 50, width: 300, height: 300))
    let back = win(2, CGRect(x: 100, y: 100, width: 300, height: 300))
    let prior = WindowUndoCapture.priorPlacements(of: [middle, back, front], roster: [front, middle, back],
                                                  dragged: nil, primaryHeight: primaryHeight)
    #expect(prior.map(\.window.id) == [3, 1, 2])
}

@Test func aWindowMissingFromTheRosterKeepsItsKnownFrameAtTheBack() {
    let gone = win(9, CGRect(x: 10, y: 20, width: 300, height: 300))
    let shown = win(1, CGRect(x: 0, y: 0, width: 300, height: 300))
    let prior = WindowUndoCapture.priorPlacements(of: [gone, shown], roster: [shown], dragged: nil,
                                                  primaryHeight: primaryHeight)
    #expect(prior.map(\.window.id) == [1, 9])
    #expect(prior.last?.frame == appKit(gone.frame))
}
