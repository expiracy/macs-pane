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
