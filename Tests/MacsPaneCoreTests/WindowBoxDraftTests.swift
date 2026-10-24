import Testing
import CoreGraphics
@testable import MacsPaneCore

private func near(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 0.0002 && abs(a.minY - b.minY) < 0.0002
        && abs(a.width - b.width) < 0.0002 && abs(a.height - b.height) < 0.0002
}

@Test func dragDrawsASelectedBoxButAClickDoesNot() {
    var draft = WindowBoxDraft(kind: .layout)
    #expect(draft.draw(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.51, y: 0.52), grid: false) == nil)
    #expect(draft.boxes.isEmpty)

    let box = draft.draw(from: CGPoint(x: 0.6, y: 0.8), to: CGPoint(x: 0.1, y: 0.2), grid: false)
    #expect(box != nil)
    #expect(draft.selection == box?.id)
    #expect(near(draft.boxes[0].rect, CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6)))
}

@Test func aBoxDrawnOverAnotherGoesBehindIt() {
    var draft = WindowBoxDraft(kind: .layout)
    let front = draft.draw(from: .zero, to: CGPoint(x: 0.6, y: 1), grid: false)!
    let behind = draft.draw(from: CGPoint(x: 0.4, y: 0), to: CGPoint(x: 1, y: 1), grid: false)!
    #expect(draft.box(behind.id)?.layer == 1)
    // In the overlap the box drawn first is in front, so it is the one a click picks.
    #expect(draft.box(at: CGPoint(x: 0.5, y: 0.5))?.id == front.id)
    #expect(draft.box(at: CGPoint(x: 0.9, y: 0.5))?.id == behind.id)
    #expect(draft.paintOrder.map(\.id) == [behind.id, front.id])
}

@Test func movingAndResizingStartFromWhereTheDragPickedTheBoxUp() {
    var draft = WindowBoxDraft(kind: .layout)
    let box = draft.draw(from: CGPoint(x: 0.1, y: 0.1), to: CGPoint(x: 0.4, y: 0.5), grid: false)!
    draft.move(box.id, from: box.rect, by: CGSize(width: 0.2, height: 0.1), grid: false)
    draft.move(box.id, from: box.rect, by: CGSize(width: 0.3, height: 0.1), grid: false)   // the same drag, further
    #expect(near(draft.box(box.id)!.rect, CGRect(x: 0.4, y: 0.2, width: 0.3, height: 0.4)))

    draft.move(box.id, from: draft.box(box.id)!.rect, by: CGSize(width: 2, height: 2), grid: false)
    #expect(near(draft.box(box.id)!.rect, CGRect(x: 0.7, y: 0.6, width: 0.3, height: 0.4)))   // stays on screen

    let start = draft.box(box.id)!.rect
    draft.resize(box.id, from: start, edges: [.left, .top], by: CGSize(width: -0.2, height: -0.1), grid: false)
    #expect(near(draft.box(box.id)!.rect, CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
}

@Test func removingTheSelectedBoxClearsTheSelection() {
    var draft = WindowBoxDraft(kind: .layout)
    let first = draft.draw(from: .zero, to: CGPoint(x: 0.5, y: 1), grid: false)!
    let second = draft.draw(from: CGPoint(x: 0.5, y: 0), to: CGPoint(x: 1, y: 1), grid: false)!
    draft.removeSelected()
    #expect(draft.boxes.map(\.id) == [first.id])
    #expect(draft.selection == nil)
    draft.remove(second.id)   // already gone: nothing happens
    #expect(draft.boxes.count == 1)
}

@Test func aLayoutNeedsABoxAndAPresetNeedsAnApp() {
    var layout = WindowBoxDraft(kind: .layout)
    #expect(!layout.canSave)
    layout.draw(from: .zero, to: CGPoint(x: 1, y: 1), grid: false)
    #expect(layout.canSave)

    var preset = WindowBoxDraft(kind: .preset)
    let box = preset.draw(from: .zero, to: CGPoint(x: 1, y: 1), grid: false)!
    #expect(!preset.canSave)
    preset.bind(.app(bundleID: "com.apple.Safari"), to: box.id)
    #expect(preset.canSave)
    preset.bind(.mostRecent, to: box.id)
    #expect(preset.canSave)
}

@Test func aSavedLayoutComesBackUnchangedThroughTheEditor() throws {
    let saved = WindowLayout(id: "mine", name: "Desk", boxes: [
        .custom(NormalizedRect(x: 0, y: 0, width: 0.6, height: 1)),
        .custom(NormalizedRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5)),
        .custom(NormalizedRect(x: 0.6, y: 0, width: 0.4, height: 0.5)),
    ])
    let draft = WindowBoxDraft(layout: saved)
    #expect(draft.editingID == "mine" && draft.name == "Desk")
    // The top-right box (bottom-left y 0.5) is at the top of the drawing.
    #expect(near(draft.boxes[1].rect, CGRect(x: 0.6, y: 0, width: 0.4, height: 0.5)))
    let back = draft.layout(named: "Desk")
    #expect(back.id == "mine")
    #expect(back.boxes == saved.boxes)
}

@Test func aSavedPresetKeepsItsAppsAndLeavesOutRemovedBoxes() {
    var preset = WindowPresetBuilder.make(from: WindowLayout.builtIns[2], name: "Three")   // thirds
    preset.slots[0].binding = .app(bundleID: "com.a")
    preset.slots[0].launchIfClosed = false
    preset.slots[1].isRemoved = true
    preset.slots[2].binding = .mostRecent
    let draft = WindowBoxDraft(preset: preset)
    #expect(draft.kind == .preset && draft.editingID == preset.id)
    #expect(draft.boxes.map(\.binding) == [.app(bundleID: "com.a"), .mostRecent])
    #expect(draft.boxes[0].launchIfClosed == false)

    let slots = draft.slots
    #expect(slots.map(\.region) == [preset.slots[0].region, preset.slots[2].region])
    #expect(slots.map(\.binding) == [.app(bundleID: "com.a"), .mostRecent])
}

@Test func startingFromOtherBoxesReplacesTheDrawing() {
    var preset = WindowBoxDraft(kind: .preset)
    preset.draw(from: .zero, to: CGPoint(x: 1, y: 1), grid: false)
    preset.replaceBoxes(with: WindowLayout.builtIns[0].boxes, bindings: [.app(bundleID: "com.a")])
    #expect(preset.boxes.count == 2)
    #expect(preset.boxes.map(\.binding) == [.app(bundleID: "com.a"), .empty])
    #expect(preset.selection == nil)

    var layout = WindowBoxDraft(kind: .layout)
    layout.replaceBoxes(with: WindowLayout.builtIns[0].boxes, bindings: [.app(bundleID: "com.a")])
    #expect(layout.boxes.allSatisfy { $0.binding == .empty })   // a layout never holds apps
}

@Test func drawnEdgesSaveExactlyOnTheScreenEdge() {
    var draft = WindowBoxDraft(kind: .layout)
    draft.draw(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 1.0 / 3, y: 1), grid: true)
    let region = draft.layout(named: "L").boxes[0]
    let unit = region.unitRect
    #expect(unit.minX == 0 && unit.minY == 0 && unit.maxY == 1)
    #expect(abs(unit.width - 1.0 / 3) < 0.0001)
}
