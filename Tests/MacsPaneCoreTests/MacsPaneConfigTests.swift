import Testing
import Foundation
@testable import MacsPaneCore

private func preset(_ id: String) -> SnapLayout {
    SnapLayout(id: id, name: id, slots: [
        SnapLayoutSlot(region: .preset(.leftHalf), binding: .app(bundleID: "com.apple.Safari"))
    ])
}

private func layout(_ id: String) -> WindowLayout {
    WindowLayout(id: id, name: id, boxes: [.custom(NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))])
}

@Test func emptyMacsPaneFileDecodesToDefaultsWithSnappingOn() throws {
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: Data("{}".utf8))
    #expect(decoded == MacsPaneConfig.default)
    #expect(decoded.snap.enabled)
    #expect(decoded.dwellMs == 1000)
    #expect(!decoded.setupCompleted)   // a file from before setup existed still gets the setup window
}

@Test func malformedPresetIsDroppedAloneAndWrongTypedFieldsFallBack() throws {
    let json = """
    { "dwellMs": "slow", "snap": 7,
      "presets": [ { "id": "good", "name": "Desk", "slots": [] }, 42 ] }
    """
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: Data(json.utf8))
    #expect(decoded.presets.map(\.id) == ["good"])
    #expect(decoded.dwellMs == 1000)
    #expect(decoded.snap == WindowSnapConfig(enabled: true))
}

@Test func macsPaneConfigRoundTrips() throws {
    var config = MacsPaneConfig()
    config.presets = [preset("p1")]
    config.windows.layouts = [layout("mine")]
    config.dwellMs = 600
    config.setupCompleted = true
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: JSONEncoder().encode(config))
    #expect(decoded == config)
}

@Test func storeSeedsFirstRunAndPersistsUpdates() {
    let url = makeTempConfigURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let store = MacsPaneConfigStore(url: url, seed: { MacsPaneConfig(presets: [preset("seeded")]) })
    #expect(store.config.presets.map(\.id) == ["seeded"])
    store.update { $0.dwellMs = 400 }

    let reloaded = MacsPaneConfigStore(url: url, seed: { nil })
    #expect(reloaded.config.presets.map(\.id) == ["seeded"])   // the seed applies only to a first run
    #expect(reloaded.config.dwellMs == 400)
}

@Test func storeSetsAnUnreadableFileAsideBeforeItCanBeOverwritten() throws {
    let url = makeTempConfigURL()
    let aside = url.deletingPathExtension().appendingPathExtension("unreadable.json")
    defer {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: aside)
    }
    try Data("[not json".utf8).write(to: url)

    let store = MacsPaneConfigStore(url: url, seed: { MacsPaneConfig(presets: [preset("seeded")]) })
    #expect(store.config == .default)   // a damaged file is not a first run: no seed
    store.update { $0.dwellMs = 400 }
    #expect(try String(contentsOf: aside, encoding: .utf8) == "[not json")
}

@Test func theHoldTimeOffersAFewChoicesAndShowsTheNearestForAnyStoredValue() {
    #expect(MacsPaneConfig.dwellChoices == [300, 600, 1000, 1500])
    #expect(MacsPaneConfig().dwellChoiceIndex == 2)          // the 1 s default
    var config = MacsPaneConfig()
    config.dwellMs = 650
    #expect(config.dwellChoiceIndex == 1)
    config.dwellMs = 5000
    #expect(config.dwellChoiceIndex == 3)
}
