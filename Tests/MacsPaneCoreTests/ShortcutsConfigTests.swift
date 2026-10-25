import Testing
import Foundation
@testable import MacsPaneCore

private let ctrlOpt1 = KeyShortcut(keyCode: 18, modifiers: [.control, .option], character: "1")
private let ctrlOpt2 = KeyShortcut(keyCode: 19, modifiers: [.control, .option], character: "2")
private let ctrlOptLeft = KeyShortcut(keyCode: 123, modifiers: [.control, .option])

private func configWithPresetAndLayout() -> MacsPaneConfig {
    var config = MacsPaneConfig()
    config.presets = [SnapLayout(id: "desk", name: "Desk", slots: [
        SnapLayoutSlot(region: .preset(.leftHalf), binding: .app(bundleID: "com.apple.Safari"))
    ])]
    config.windows.layouts = [WindowLayout(id: "mine", name: "Mine", boxes: [
        .custom(NormalizedRect(x: 0, y: 0, width: 0.3, height: 1)),
        .custom(NormalizedRect(x: 0.3, y: 0, width: 0.7, height: 1)),
    ])]
    return config
}

@Test func aPresetKeepsTheShortcutGivenIt() {
    var config = configWithPresetAndLayout()
    config.setShortcut(ctrlOpt1, for: .preset(id: "desk"))
    #expect(config.shortcut(for: .preset(id: "desk")) == ctrlOpt1)
    config.setShortcut(ctrlOpt2, for: .preset(id: "desk"))
    #expect(config.shortcut(for: .preset(id: "desk")) == ctrlOpt2)
    #expect(config.shortcuts.count == 1)
    config.setShortcut(nil, for: .preset(id: "desk"))
    #expect(config.shortcut(for: .preset(id: "desk")) == nil)
}

@Test func aComboGivenToSomethingElseLeavesWhatHadIt() {
    var config = configWithPresetAndLayout()
    config.setShortcut(ctrlOpt1, for: .preset(id: "desk"))
    config.setShortcut(ctrlOpt1, for: .layoutBox(layoutID: "halves", box: 0))
    #expect(config.shortcut(for: .preset(id: "desk")) == nil)
    #expect(config.shortcut(for: .layoutBox(layoutID: "halves", box: 0)) == ctrlOpt1)
}

@Test func savingALayoutsBoxShortcutsReplacesOnlyThatLayouts() {
    var config = configWithPresetAndLayout()
    config.setShortcut(ctrlOptLeft, for: .layoutBox(layoutID: "halves", box: 0))
    config.setShortcut(ctrlOpt1, for: .layoutBox(layoutID: "mine", box: 0))
    config.setBoxShortcuts([1: ctrlOpt2], ofLayout: "mine")
    #expect(config.boxShortcuts(ofLayout: "mine") == [1: ctrlOpt2])
    #expect(config.boxShortcuts(ofLayout: "halves") == [0: ctrlOptLeft])
    // A combo the saved layout takes leaves whatever else had it.
    config.setBoxShortcuts([0: ctrlOptLeft], ofLayout: "mine")
    #expect(config.boxShortcuts(ofLayout: "halves").isEmpty)
}

@Test func deletingAPresetOrYourLayoutDropsItsShortcutsButADeletedBuiltInKeepsThem() {
    var config = configWithPresetAndLayout()
    config.setShortcut(ctrlOpt1, for: .preset(id: "desk"))
    config.setShortcut(ctrlOpt2, for: .layoutBox(layoutID: "mine", box: 1))
    config.setShortcut(ctrlOptLeft, for: .layoutBox(layoutID: "halves", box: 0))
    _ = config.removePreset("desk")
    _ = config.removeLayout("mine")
    _ = config.removeLayout("halves")
    #expect(config.shortcuts.map(\.action) == [.layoutBox(layoutID: "halves", box: 0)])
    // ...but only what exists answers a key: the deleted built-in is silent until it is restored.
    #expect(config.activeShortcuts.isEmpty)
    config.windows.restoreBuiltIns()
    #expect(config.activeShortcuts.map(\.shortcut) == [ctrlOptLeft])
}

@Test func onlyShortcutsWhoseTargetExistsAreActive() {
    var config = configWithPresetAndLayout()
    config.shortcuts = [
        AssignedShortcut(shortcut: ctrlOpt1, action: .preset(id: "gone")),
        AssignedShortcut(shortcut: ctrlOpt2, action: .layoutBox(layoutID: "mine", box: 5)),
        AssignedShortcut(shortcut: ctrlOptLeft, action: .layoutBox(layoutID: "mine", box: 1)),
        AssignedShortcut(shortcut: KeyShortcut(keyCode: 18, modifiers: []), action: .preset(id: "desk")),
    ]
    #expect(config.activeShortcuts.map(\.shortcut) == [ctrlOptLeft])
}

@Test func shortcutsRoundTripAndAnOlderFileHasNone() throws {
    var config = configWithPresetAndLayout()
    config.setShortcut(ctrlOpt1, for: .preset(id: "desk"))
    config.setShortcut(ctrlOpt2, for: .layoutBox(layoutID: "halves", box: 1))
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: JSONEncoder().encode(config))
    #expect(decoded == config)
    let old = try JSONDecoder().decode(MacsPaneConfig.self, from: Data(#"{ "dwellMs": 600 }"#.utf8))
    #expect(old.shortcuts.isEmpty)
}

@Test func aMalformedShortcutIsDroppedAlone() throws {
    let json = """
    { "shortcuts": [
        { "shortcut": { "keyCode": 18, "modifiers": 3 }, "action": { "kind": "preset", "id": "desk" } },
        { "shortcut": {}, "action": { "kind": "preset", "id": "desk" } },
        { "shortcut": { "keyCode": 19, "modifiers": 3 }, "action": { "kind": "teleport" } },
        { "shortcut": { "keyCode": 20, "modifiers": 3 }, "action": { "kind": "layoutBox", "layoutID": "halves", "box": 1 } }
    ] }
    """
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: Data(json.utf8))
    #expect(decoded.shortcuts.map(\.action) == [.preset(id: "desk"), .layoutBox(layoutID: "halves", box: 1)])
}

@Test func theShortcutListReadsPresetsThenLayoutBoxesInTheMenusOrder() {
    var config = configWithPresetAndLayout()
    config.presets.append(SnapLayout(id: "late", name: "Late", slots: config.presets[0].slots))
    let keys = (18...23).map { KeyShortcut(keyCode: UInt16($0), modifiers: [.control, .option]) }
    config.setShortcut(keys[0], for: .layoutBox(layoutID: "mine", box: 1))
    config.setShortcut(keys[1], for: .layoutBox(layoutID: "halves", box: 1))
    config.setShortcut(keys[2], for: .preset(id: "late"))
    config.setShortcut(keys[3], for: .layoutBox(layoutID: "halves", box: 0))
    config.setShortcut(keys[4], for: .preset(id: "desk"))
    config.setShortcut(keys[5], for: .preset(id: "gone"))   // not listed: nothing to run
    config.windows.moveLayout(from: config.windows.layoutCatalog.count - 1, to: 0)   // "mine" first
    #expect(config.shortcutList.map(\.action) == [
        .preset(id: "desk"), .preset(id: "late"),
        .layoutBox(layoutID: "mine", box: 1),
        .layoutBox(layoutID: "halves", box: 0), .layoutBox(layoutID: "halves", box: 1),
    ])
}

@Test func aShortcutSwitchedOffStaysListedButAnswersNoKey() {
    var config = configWithPresetAndLayout()
    config.setShortcut(ctrlOpt1, for: .preset(id: "desk"))
    config.setShortcutEnabled(false, for: .preset(id: "desk"))
    #expect(config.activeShortcuts.isEmpty)
    #expect(config.shortcutList.map(\.action) == [.preset(id: "desk")])
    #expect(config.shortcutList.first?.isEnabled == false)
    config.setShortcutEnabled(true, for: .preset(id: "desk"))
    #expect(config.activeShortcuts.map(\.shortcut) == [ctrlOpt1])
}

@Test func savingTheSameKeysKeepsAShortcutOffButNewKeysSwitchItOn() {
    var config = configWithPresetAndLayout()
    config.setShortcut(ctrlOpt1, for: .preset(id: "desk"))
    config.setBoxShortcuts([0: ctrlOpt2], ofLayout: "mine")
    config.setShortcutEnabled(false, for: .preset(id: "desk"))
    config.setShortcutEnabled(false, for: .layoutBox(layoutID: "mine", box: 0))
    // The editor saves everything again, unchanged.
    config.setShortcut(ctrlOpt1, for: .preset(id: "desk"))
    config.setBoxShortcuts([0: ctrlOpt2], ofLayout: "mine")
    #expect(config.activeShortcuts.isEmpty)
    // New keys are meant to be used.
    config.setShortcut(ctrlOptLeft, for: .preset(id: "desk"))
    #expect(config.activeShortcuts.map(\.shortcut) == [ctrlOptLeft])
}

@Test func aShortcutSavedBeforeTheSwitchExistedIsOn() throws {
    let json = #"{ "shortcut": { "keyCode": 18, "modifiers": 3 }, "action": { "kind": "preset", "id": "desk" } }"#
    #expect(try JSONDecoder().decode(AssignedShortcut.self, from: Data(json.utf8)).isEnabled)
}
