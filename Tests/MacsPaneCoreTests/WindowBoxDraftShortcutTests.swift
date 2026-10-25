import Testing
import CoreGraphics
@testable import MacsPaneCore

private let ctrlOpt1 = KeyShortcut(keyCode: 18, modifiers: [.control, .option], character: "1")
private let ctrlOpt2 = KeyShortcut(keyCode: 19, modifiers: [.control, .option], character: "2")

private let thirds = WindowLayout.builtIns.first { $0.id == "thirds" }!

@Test func aLayoutOpensWithEachBoxsShortcutAndSavesThemInBoxOrder() {
    var mine = thirds
    mine.id = "mine"
    var draft = WindowBoxDraft(layout: mine, boxShortcuts: [0: ctrlOpt1, 2: ctrlOpt2])
    #expect(draft.boxes.map(\.shortcut) == [ctrlOpt1, nil, ctrlOpt2])
    // Taking the first box out moves the third box's shortcut to its new place.
    draft.remove(draft.boxes[0].id)
    #expect(draft.boxShortcuts == [1: ctrlOpt2])
}

@Test func aComboGivenToOneBoxLeavesTheBoxThatHadIt() {
    var mine = thirds
    mine.id = "mine"
    var draft = WindowBoxDraft(layout: mine, boxShortcuts: [0: ctrlOpt1])
    draft.setShortcut(ctrlOpt1, forBox: draft.boxes[1].id)
    #expect(draft.boxShortcuts == [1: ctrlOpt1])
    draft.setShortcut(nil, forBox: draft.boxes[1].id)
    #expect(draft.boxShortcuts.isEmpty)
}

@Test func aPresetOpensWithItsShortcut() {
    let preset = SnapLayout(id: "desk", name: "Desk", slots: [
        SnapLayoutSlot(region: .preset(.leftHalf), binding: .app(bundleID: "com.apple.Safari"))
    ])
    var draft = WindowBoxDraft(preset: preset, shortcut: ctrlOpt1)
    #expect(draft.shortcut == ctrlOpt1)
    draft.shortcut = nil
    #expect(draft.shortcut == nil)
}
