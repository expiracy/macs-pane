import Testing
import Foundation
@testable import MacsPaneCore

private let ctrlOptLeft = KeyShortcut(keyCode: 123, modifiers: [.control, .option])
private let halves = WindowLayout.builtIns.first { $0.id == "halves" }!

private func wideHalves(named name: String = "Halves") -> WindowLayout {
    WindowLayout(id: "halves", name: name, boxes: [
        .custom(NormalizedRect(x: 0, y: 0, width: 0.7, height: 1)),
        .custom(NormalizedRect(x: 0.7, y: 0, width: 0.3, height: 1)),
    ])
}

@Test func restoringBringsBackDeletedBuiltInsOutOfTheNotch() {
    var config = MacsPaneConfig()
    _ = config.removeLayout("quarters")
    #expect(config.canRestoreBuiltInLayouts)
    config.restoreBuiltInLayouts()
    #expect(config.windows.layoutCatalog.contains { $0.id == "quarters" })
    #expect(!config.windows.dragBarLayoutIDs.contains("quarters"))
    #expect(!config.canRestoreBuiltInLayouts)
}

@Test func restoringAnEditedBuiltInKeepsYourEditBesideTheOriginal() throws {
    var config = MacsPaneConfig()
    config.windows.layouts = [wideHalves()]
    config.setShortcut(ctrlOptLeft, for: .layoutBox(layoutID: "halves", box: 0))
    #expect(config.canRestoreBuiltInLayouts)
    config.restoreBuiltInLayouts()

    let catalog = config.windows.layoutCatalog
    let edit = try #require(catalog.first { $0.boxes == wideHalves().boxes })
    #expect(edit.id != "halves")
    #expect(edit.name == "Halves (edited)")   // two "Halves" would be told apart by shape alone
    #expect(catalog.first { $0.id == "halves" } == halves)
    // The edit keeps its place, with the original right after it, and keeps the notch and its keys.
    #expect(catalog.map(\.id).prefix(2) == [edit.id, "halves"])
    #expect(config.windows.dragBarLayoutIDs.contains(edit.id))
    #expect(!config.windows.dragBarLayoutIDs.contains("halves"))
    #expect(config.boxShortcuts(ofLayout: edit.id) == [0: ctrlOptLeft])
    #expect(config.boxShortcuts(ofLayout: "halves").isEmpty)
    #expect(!config.canRestoreBuiltInLayouts)
}

@Test func anEditRenamedByYouKeepsItsName() {
    var config = MacsPaneConfig()
    config.windows.layouts = [wideHalves(named: "Wide")]
    config.restoreBuiltInLayouts()
    #expect(config.windows.layoutCatalog.map(\.name).prefix(2) == ["Wide", "Halves"])
}

@Test func aBuiltInSavedUnchangedIsNotCopied() {
    var config = MacsPaneConfig()
    config.windows.layouts = [halves]
    #expect(!config.canRestoreBuiltInLayouts)
    config.restoreBuiltInLayouts()
    #expect(config.windows.layoutCatalog.count == WindowLayout.builtIns.count)
}

@Test func aDeletedBuiltInComesBackInItsPlaceWhenYouNeverReorderedTheList() {
    var config = MacsPaneConfig()
    _ = config.removeLayout("twoThirds")
    config.restoreBuiltInLayouts()
    #expect(config.windows.layoutCatalog.map(\.id) == WindowLayout.builtIns.map(\.id))
}
