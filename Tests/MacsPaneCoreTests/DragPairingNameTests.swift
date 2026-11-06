import Testing
@testable import MacsPaneCore

@Test func aPairingTileNamesOnlyTheAppsJoiningTheDraggedWindow() {
    #expect(DragPairing.tileName(appNames: ["Safari", "Mail"]) == "+ Mail")
    #expect(DragPairing.tileName(appNames: ["Safari", "Mail", "Calendar"]) == "+ Mail, Calendar")
}

@Test func aPairingOfOneWindowIsNamedForIt() {
    #expect(DragPairing.tileName(appNames: ["Safari"]) == "Safari")
    #expect(DragPairing.tileName(appNames: []) == "")
}
