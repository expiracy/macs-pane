import Testing
import Foundation
@testable import MacsPaneCore

private let mine = WindowLayout(id: "mine", name: "Mine", boxes: [.preset(.leftHalf)])

@Test func theLayoutListFollowsTheSavedOrderWithNewLayoutsAtTheEnd() {
    var config = WindowsConfig(layouts: [mine])
    #expect(config.layoutCatalog.map(\.id) == ["halves", "twoThirds", "thirds", "quarters", "centre", "fill", "mine"])
    config.layoutOrder = ["fill", "gone", "halves"]
    #expect(config.layoutCatalog.map(\.id) == ["fill", "halves", "twoThirds", "thirds", "quarters", "centre", "mine"])
}

@Test func aConfigWithoutALayoutOrderKeepsTheDefaultOrder() throws {
    let json = #"{ "enabled": true, "layouts": [] }"#
    let decoded = try JSONDecoder().decode(WindowsConfig.self, from: Data(json.utf8))
    #expect(decoded.layoutOrder.isEmpty)
    var config = WindowsConfig()
    config.layoutOrder = ["fill", "halves"]
    #expect(try JSONDecoder().decode(WindowsConfig.self, from: JSONEncoder().encode(config)) == config)
}

@Test func movingALayoutReordersTheListAndTheNotchFollows() {
    var config = WindowsConfig(layouts: [mine], dragBarLayoutIDs: ["halves", "quarters", "mine"])
    config.moveLayout(from: 6, to: 0)
    #expect(config.layoutCatalog.map(\.id) == ["mine", "halves", "twoThirds", "thirds", "quarters", "centre", "fill"])
    #expect(config.dragBarLayoutIDs == ["mine", "halves", "quarters"])
    config.moveLayout(from: 1, to: 9)
    #expect(config.layoutCatalog.map(\.id).last == "halves")
    #expect(config.dragBarLayoutIDs == ["mine", "quarters", "halves"])
}

@Test func aLayoutSwitchedOnTakesItsPlaceInTheListOrder() {
    var config = WindowsConfig(dragBarLayoutIDs: ["halves", "fill"])
    #expect(config.toggleInBar("quarters") == .offered)
    #expect(config.dragBarLayoutIDs == ["halves", "quarters", "fill"])
    #expect(config.toggleInBar("halves") == .takenOut)
    #expect(config.dragBarLayoutIDs == ["quarters", "fill"])
    #expect(config.toggleInBar("missing") == .unknown)
}

@Test func movingAPresetReordersThePresets() {
    var config = MacsPaneConfig(presets: ["a", "b", "c"].map { SnapLayout(id: $0, name: $0, slots: []) })
    config.movePreset(from: 2, to: 0)
    #expect(config.presets.map(\.id) == ["c", "a", "b"])
    config.movePreset(from: 5, to: 0)
    #expect(config.presets.map(\.id) == ["c", "a", "b"])
}

@Test func aDeletedPresetComesBackWhereItWas() {
    var config = MacsPaneConfig(presets: ["a", "b", "c"].map { SnapLayout(id: $0, name: $0, slots: []) })
    let removed = config.removePreset("b")
    #expect(config.presets.map(\.id) == ["a", "c"])
    config.restore(try! #require(removed))
    #expect(config.presets.map(\.id) == ["a", "b", "c"])
    #expect(config.removePreset("missing") == nil)
}

@Test func aDeletedLayoutComesBackToItsPlaceInTheListAndTheNotch() {
    var config = WindowsConfig(layouts: [mine], dragBarLayoutIDs: ["halves", "mine", "fill"])
    config.moveLayout(from: 6, to: 1)
    let before = config
    let removed = config.removeLayout("mine")
    #expect(!config.layoutCatalog.contains { $0.id == "mine" })
    #expect(config.dragBarLayoutIDs == ["halves", "fill"])
    config.restore(try! #require(removed))
    #expect(config == before)
    #expect(config.removeLayout("missing") == nil)
}

@Test func aBuiltInLayoutCanBeDeletedAndComesBack() {
    var config = WindowsConfig(dragBarLayoutIDs: ["halves", "quarters", "fill"])
    let before = config
    let removed = config.removeLayout("quarters")
    #expect(removed != nil)
    #expect(!config.layoutCatalog.contains { $0.id == "quarters" })
    #expect(config.dragBarLayoutIDs == ["halves", "fill"])
    #expect(config.deletedBuiltIns == ["quarters"])
    config.restore(try! #require(removed))
    #expect(config.layoutCatalog.map(\.id) == before.layoutCatalog.map(\.id))
    #expect(config.dragBarLayoutIDs == before.dragBarLayoutIDs)
}

@Test func deletedBuiltInsComeBackTogetherAndSurviveSaving() throws {
    var config = WindowsConfig()
    _ = config.removeLayout("halves")
    _ = config.removeLayout("thirds")
    let saved = try JSONDecoder().decode(WindowsConfig.self, from: JSONEncoder().encode(config))
    #expect(saved.deletedBuiltIns == ["halves", "thirds"])
    config.restoreBuiltIns()
    #expect(config.deletedBuiltIns.isEmpty)
    #expect(config.layoutCatalog.map(\.id) == WindowsConfig().layoutCatalog.map(\.id))
}
