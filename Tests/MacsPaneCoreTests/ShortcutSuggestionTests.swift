import Testing
@testable import MacsPaneCore

private let ctrlOptLeft = KeyShortcut(keyCode: 123, modifiers: [.control, .option])
private let ctrlOpt1 = KeyShortcut(keyCode: 18, modifiers: [.control, .option], character: "1")

@Test func setupSuggestsHalvesFillAndCentreKeys() {
    let config = MacsPaneConfig()
    #expect(config.shortcutSuggestions.map(\.name) == ["Left half", "Right half", "Fill", "Centre"])
    #expect(config.shortcutSuggestions.map(\.action) == [
        .layoutBox(layoutID: "halves", box: 0), .layoutBox(layoutID: "halves", box: 1),
        .layoutBox(layoutID: "fill", box: 0), .layoutBox(layoutID: "centre", box: 0),
    ])
    #expect(config.shortcutSuggestions[0].shortcut == ctrlOptLeft)
    #expect(config.shortcutSuggestions.allSatisfy { $0.shortcut.isUsable })
}

@Test func aSuggestionForADeletedLayoutIsLeftOut() {
    var config = MacsPaneConfig()
    _ = config.removeLayout("fill")
    #expect(config.shortcutSuggestions.map(\.name) == ["Left half", "Right half", "Centre"])
}

@Test func suggestionsStartOffAndSwitchOnWithTheirKeys() throws {
    var config = MacsPaneConfig()
    let left = try #require(config.shortcutSuggestions.first)
    #expect(!config.isOn(left))
    #expect(config.keys(for: left) == ctrlOptLeft)
    #expect(config.activeShortcuts.isEmpty)

    config.setSuggestion(left, on: true)
    #expect(config.isOn(left))
    #expect(config.activeShortcuts.map(\.shortcut) == [ctrlOptLeft])

    // Off keeps the keys, switched off, as the menu's switch does.
    config.setSuggestion(left, on: false)
    #expect(!config.isOn(left))
    #expect(config.activeShortcuts.isEmpty)
    #expect(config.shortcut(for: left.action) == ctrlOptLeft)
}

@Test func aBoxWithKeysOfYourOwnKeepsThemWhenSwitchedOn() throws {
    var config = MacsPaneConfig()
    config.setShortcut(ctrlOpt1, for: .layoutBox(layoutID: "halves", box: 0))
    config.setShortcutEnabled(false, for: .layoutBox(layoutID: "halves", box: 0))
    let left = try #require(config.shortcutSuggestions.first)
    #expect(config.keys(for: left) == ctrlOpt1)
    config.setSuggestion(left, on: true)
    #expect(config.activeShortcuts.map(\.shortcut) == [ctrlOpt1])
}
