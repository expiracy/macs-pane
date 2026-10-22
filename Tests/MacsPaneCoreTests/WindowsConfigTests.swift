import Testing
import Foundation
@testable import MacsPaneCore

@Test func notchPlusPlusImportKeepsPresetsWhenWindowsBlockIsAbsent() throws {
    let json = """
    { "enabled": true, "snapLayouts": [{
      "id": "scene-1", "name": "Desk", "slots": [{
        "id": "slot-1", "region": { "kind": "preset", "zone": "leftHalf" },
        "binding": { "kind": "app", "bundleID": "com.apple.Safari" },
        "launchIfClosed": true
      }]
    }] }
    """
    let decoded = try JSONDecoder().decode(NotchPlusPlusWindowSettings.self, from: Data(json.utf8))
    #expect(decoded.windows == WindowsConfig())
    #expect(decoded.snapLayouts.count == 1)
    #expect(decoded.snapLayouts[0].id == "scene-1")
    #expect(decoded.snapLayouts[0].slots[0].binding == .app(bundleID: "com.apple.Safari"))
    #expect(decoded.snapLayouts[0].slots[0].launchIfClosed)
}

@Test func presetProfileRoundTripsWithoutChangingItsSlots() throws {
    let scene = SnapLayout(id: "scene-2", name: "Meeting", slots: [
        SnapLayoutSlot(id: "recent", region: .preset(.rightHalf), binding: .mostRecent),
        SnapLayoutSlot(id: "blank", region: .preset(.leftHalf), binding: .empty)
    ], profileID: "meeting")
    let decoded = try JSONDecoder().decode(SnapLayout.self, from: JSONEncoder().encode(scene))
    #expect(decoded == scene)
    #expect(decoded.profileID == "meeting")
    #expect(decoded.slots.map(\.binding) == [.mostRecent, .empty])
}

@Test func windowsConfigKeepsChosenLayoutOrder() throws {
    var config = WindowsConfig()
    config.dragBarLayoutIDs = ["quarters", "halves", "fill"]
    let decoded = try JSONDecoder().decode(WindowsConfig.self, from: JSONEncoder().encode(config))
    #expect(decoded.dragBarLayoutIDs == ["quarters", "halves", "fill"])
}

@Test func builtInLayoutsProvideTheDraftsSixDistinctShapes() {
    let builtIns = WindowLayout.builtIns
    #expect(builtIns.map(\.id) == ["halves", "twoThirds", "thirds", "quarters", "centre", "fill"])
    #expect(builtIns.map { $0.boxes.count } == [2, 2, 3, 4, 1, 1])
    #expect(builtIns[0].boxes[0].unitRect == CGRect(x: 0, y: 0, width: 0.5, height: 1))
    #expect(builtIns[3].boxes[3].unitRect == CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
}

@Test func legacyPresetRetainsItsOwnGeometryWithoutANewLayoutID() throws {
    let old = SnapLayout(id: "older", name: "My desk", slots: [
        SnapLayoutSlot(id: "a", region: .preset(.leftHalf), binding: .app(bundleID: "com.apple.Safari")),
        SnapLayoutSlot(id: "b", region: .preset(.rightHalf), binding: .mostRecent)
    ])
    let decoded = try JSONDecoder().decode(SnapLayout.self, from: JSONEncoder().encode(old))
    #expect(decoded.layoutID == nil)
    #expect(decoded.slots.map(\.region) == [.preset(.leftHalf), .preset(.rightHalf)])
}

@Test func newPresetRemembersItsParentLayout() throws {
    let scene = SnapLayout(name: "Quarters set", layoutID: "quarters")
    let decoded = try JSONDecoder().decode(SnapLayout.self, from: JSONEncoder().encode(scene))
    #expect(decoded.layoutID == "quarters")
}

@Test func dragBarHitTestingPicksTheBoxShownUnderThePointer() {
    let halves = WindowLayout.builtIns[0]
    #expect(halves.boxIndex(atTopLeftUnit: CGPoint(x: 0.2, y: 0.5)) == 0)
    #expect(halves.boxIndex(atTopLeftUnit: CGPoint(x: 0.8, y: 0.5)) == 1)
    let centre = WindowLayout.builtIns[4]
    #expect(centre.boxIndex(atTopLeftUnit: CGPoint(x: 0.5, y: 0.5)) == 0)
    #expect(centre.boxIndex(atTopLeftUnit: CGPoint(x: 0.05, y: 0.5)) == nil)
}

@Test func malformedSavedLayoutDoesNotResetTheNotchOrOtherLayouts() throws {
    let json = """
    { "enabled": true, "windows": { "enabled": true, "layouts": [
      { "id": "good", "name": "Tall", "boxes": [
        { "kind": "custom", "rect": { "x": 0.1, "y": 0.1, "width": 0.4, "height": 0.8 } }
      ] },
      { "id": "bad", "name": "Broken", "boxes": "not-an-array" }
    ], "dragBarLayoutIDs": ["good"] } }
    """
    let decoded = try JSONDecoder().decode(NotchPlusPlusWindowSettings.self, from: Data(json.utf8))
    #expect(decoded.windows.layouts.map(\.id) == ["good"])
    #expect(decoded.windows.dragBarLayoutIDs == ["good"])
}

@Test func emptyDragBarResolvesToNoPickerTargets() {
    var config = WindowsConfig()
    config.dragBarLayoutIDs = []
    #expect(config.resolvedDragBarLayouts.isEmpty)
    config.dragBarLayoutIDs = ["quarters", "missing", "halves"]
    #expect(config.resolvedDragBarLayouts.map(\.id) == ["quarters", "halves"])
}

@Test func malformedDraftProfileFieldsDoNotDiscardLegacyPresets() throws {
    let json = """
    { "enabled": true, "snapLayouts": [
      { "id": "legacy", "name": "Desk", "slots": [], "profileID": 42, "layoutID": [] }
    ] }
    """
    let decoded = try JSONDecoder().decode(NotchPlusPlusWindowSettings.self, from: Data(json.utf8))
    #expect(decoded.snapLayouts.map(\.id) == ["legacy"])
    #expect(decoded.snapLayouts[0].profileID == nil)
    #expect(decoded.snapLayouts[0].layoutID == nil)
}
