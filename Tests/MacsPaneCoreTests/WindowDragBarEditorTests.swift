import Testing
import Foundation
@testable import MacsPaneCore

private let catalog = WindowLayout.builtIns
    + [WindowLayout(id: "mine", name: "Mine", boxes: [.custom(NormalizedRect(x: 0, y: 0, width: 1, height: 1))])]

@Test func tickingALayoutOffersItInTheBarAndTickingAgainTakesItOut() {
    var ids = ["halves"]
    #expect(WindowDragBarEditor.toggle("mine", in: &ids, catalog: catalog) == .offered)
    #expect(ids == ["halves", "mine"])
    #expect(WindowDragBarEditor.toggle("halves", in: &ids, catalog: catalog) == .takenOut)
    #expect(ids == ["mine"])
}

@Test func theBarTakesASixthLayoutAndMore() {
    var ids = WindowsConfig.defaultDragBarLayoutIDs
    #expect(WindowDragBarEditor.toggle("centre", in: &ids, catalog: catalog) == .offered)
    #expect(WindowDragBarEditor.insert("mine", at: 0, in: &ids, catalog: catalog) == .offered)
    #expect(ids == ["mine"] + WindowsConfig.defaultDragBarLayoutIDs + ["centre"])
}

@Test func droppingALayoutTheBarAlreadyOffersChangesNothing() {
    var ids = ["halves", "quarters"]
    #expect(WindowDragBarEditor.insert("quarters", at: 0, in: &ids, catalog: catalog) == .alreadyOffered)
    #expect(ids == ["halves", "quarters"])
    #expect(WindowDragBarEditor.insert("fill", at: 1, in: &ids, catalog: catalog) == .offered)
    #expect(ids == ["halves", "fill", "quarters"])
}

@Test func anUnknownLayoutNeverEntersTheBar() {
    var ids: [String] = []
    #expect(WindowDragBarEditor.toggle("ghost", in: &ids, catalog: catalog) == .unknown)
    #expect(ids.isEmpty)
}

@Test func takingOneOutKeepsTheOrderOfTheRest() {
    var ids = ["halves", "quarters", "fill"]
    WindowDragBarEditor.remove("quarters", from: &ids)
    #expect(ids == ["halves", "fill"])
}

@Test func droppingATileReordersTheBarWithoutLosingALayout() {
    var ids = ["halves", "quarters", "fill"]
    WindowDragBarEditor.move(from: 2, to: 0, in: &ids)
    #expect(ids == ["fill", "halves", "quarters"])
    WindowDragBarEditor.move(from: 0, to: 9, in: &ids)
    #expect(ids == ["halves", "quarters", "fill"])
    WindowDragBarEditor.move(from: 1, to: 1, in: &ids)
    #expect(ids == ["halves", "quarters", "fill"])
}

@Test func deletingALayoutPrunesItFromTheBar() {
    let ids = ["halves", "mine", "gone", "halves"]
    #expect(WindowDragBarEditor.pruned(ids, catalog: WindowLayout.builtIns) == ["halves"])
    #expect(WindowDragBarEditor.pruned(ids, catalog: catalog) == ["halves", "mine"])
}

@Test func aLongSavedBarResolvesEveryLayoutInOrder() {
    var config = WindowsConfig()
    config.dragBarLayoutIDs = ["halves", "quarters", "fill", "thirds", "centre", "twoThirds"]
    #expect(config.resolvedDragBarLayouts.map(\.id) == ["halves", "quarters", "fill", "thirds", "centre", "twoThirds"])
    #expect(config.offersInBar("twoThirds"))
}

@Test func anOldConfigWithoutABarDecodesToTheFiveLayoutDefault() throws {
    let json = #"{ "enabled": true, "layouts": [] }"#
    let decoded = try JSONDecoder().decode(WindowsConfig.self, from: Data(json.utf8))
    #expect(decoded.dragBarLayoutIDs == ["halves", "twoThirds", "thirds", "quarters", "fill"])
}

@Test func theOldThreeLayoutDefaultMovesToFiveButAChosenBarStays() {
    var stock = WindowsConfig(dragBarLayoutIDs: ["halves", "quarters", "fill"])
    stock.adoptFiveLayoutDefault()
    #expect(stock.dragBarLayoutIDs == WindowsConfig.defaultDragBarLayoutIDs)
    var chosen = WindowsConfig(dragBarLayoutIDs: ["fill", "halves", "quarters"])
    chosen.adoptFiveLayoutDefault()
    #expect(chosen.dragBarLayoutIDs == ["fill", "halves", "quarters"])
}

@Test func aMacsPaneFileOnTheOldBarDefaultMigrates() {
    let mac = MacsPaneConfig(windows: WindowsConfig(dragBarLayoutIDs: ["halves", "quarters", "fill"]))
    #expect(mac.migrated().windows.dragBarLayoutIDs == WindowsConfig.defaultDragBarLayoutIDs)
}
