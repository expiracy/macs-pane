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

@Test func importFromNotchPlusPlusCarriesWindowsAndForcesSnappingOn() {
    var notch = NotchPlusPlusWindowSettings()
    notch.windowSnap.enabled = false
    notch.windowSnap.showFullScreenPreview = false
    notch.windows.layouts = [layout("mine")]
    notch.windows.dragBarLayoutIDs = ["mine", "fill"]
    notch.snapLayouts = [preset("p1")]
    notch.hoverExpandDelayMs = 700

    let imported = MacsPaneConfig.imported(from: notch)
    #expect(imported.snap.enabled)
    #expect(imported.snap.showFullScreenPreview == false)
    #expect(imported.windows.dragBarLayoutIDs == ["mine", "fill"])
    #expect(imported.windows.layouts.map(\.id) == ["mine"])
    #expect(imported.presets.map(\.id) == ["p1"])
    #expect(imported.dwellMs == 700)
}

@Test func mergeAddsOnlyMissingLayoutsAndPresetsAndKeepsSettings() {
    var config = MacsPaneConfig(presets: [preset("p1")])
    config.windows.layouts = [layout("mine")]
    config.snap.showFullScreenPreview = false
    var notch = NotchPlusPlusWindowSettings()
    notch.snapLayouts = [preset("p1"), preset("p2")]
    notch.windows.layouts = [layout("mine"), layout("theirs")]
    notch.windowSnap.showFullScreenPreview = true

    #expect(config.merge(from: notch) == 2)
    #expect(config.presets.map(\.id) == ["p1", "p2"])
    #expect(config.windows.layouts.map(\.id) == ["mine", "theirs"])
    #expect(config.snap.showFullScreenPreview == false)
    #expect(config.merge(from: notch) == 0)   // a second import adds nothing
}

@Test func notchPlusPlusFileYieldsItsWindowSettingsAndGarbageYieldsNil() throws {
    let presets = String(decoding: try JSONEncoder().encode([preset("p1")]), as: UTF8.self)
    let file = """
    { "schemaVersion": 10, "modules": { "keyboard": {}, "notch": {
        "enabled": true, "hoverExpandDelayMs": 700, "snapLayouts": \(presets),
        "windows": { "dragBarLayoutIDs": ["fill"] }, "calendar": { "anything": 1 } } } }
    """
    let settings = MacsPaneConfig.notchPlusPlusSettings(fromFile: Data(file.utf8))
    #expect(settings?.snapLayouts.map(\.id) == ["p1"])
    #expect(settings?.windows.dragBarLayoutIDs == ["fill"])
    #expect(settings?.hoverExpandDelayMs == 700)
    #expect(MacsPaneConfig.notchPlusPlusSettings(fromFile: Data("nope".utf8)) == nil)
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
