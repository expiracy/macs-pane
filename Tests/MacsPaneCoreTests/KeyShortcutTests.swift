import Testing
import Foundation
@testable import MacsPaneCore

@Test func shortcutReadsModifiersInTheMacOrderThenItsKey() {
    let shortcut = KeyShortcut(keyCode: 18, modifiers: [.command, .shift, .option, .control], character: "1")
    #expect(shortcut.displayName == "⌃⌥⇧⌘1")
}

@Test func keysThatTypeNothingAreNamedByTheirSymbol() {
    #expect(KeyShortcut(keyCode: 123, modifiers: [.control, .option]).displayName == "⌃⌥←")
    #expect(KeyShortcut(keyCode: 96, modifiers: []).displayName == "F5")
    #expect(KeyShortcut(keyCode: 49, modifiers: [.option], character: " ").displayName == "⌥Space")
}

@Test func aShortcutNeedsCommandControlOrOptionUnlessItIsAFunctionKey() {
    #expect(KeyShortcut(keyCode: 18, modifiers: [.control], character: "1").isUsable)
    #expect(KeyShortcut(keyCode: 18, modifiers: [.option, .shift], character: "1").isUsable)
    #expect(!KeyShortcut(keyCode: 18, modifiers: [], character: "1").isUsable)      // would eat every "1" typed
    #expect(!KeyShortcut(keyCode: 18, modifiers: [.shift], character: "!").isUsable)
    #expect(KeyShortcut(keyCode: 96, modifiers: []).isUsable)                         // F5 alone
}

@Test func shortcutRoundTripsAndAFileWithoutAKeyCodeIsRejected() throws {
    let shortcut = KeyShortcut(keyCode: 18, modifiers: [.control, .option], character: "1")
    let decoded = try JSONDecoder().decode(KeyShortcut.self, from: JSONEncoder().encode(shortcut))
    #expect(decoded == shortcut)
    let bare = try JSONDecoder().decode(KeyShortcut.self, from: Data(#"{ "keyCode": 18 }"#.utf8))
    #expect(bare == KeyShortcut(keyCode: 18, modifiers: []))
    #expect(throws: (any Error).self) { try JSONDecoder().decode(KeyShortcut.self, from: Data("{}".utf8)) }
}
