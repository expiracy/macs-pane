import Testing
import Foundation
@testable import MacsPaneCore

@Test func defaultHasNoPresets() {
    #expect(MacsPaneConfig.default.presets.isEmpty)
}

@Test func presetsRoundTripThroughTheConfigFile() throws {
    var cfg = MacsPaneConfig.default
    cfg.presets = [
        SnapLayout(id: "coding", name: "Coding", slots: [
            SnapLayoutSlot(id: "s1", region: .preset(.leftTwoThirds), binding: .app(bundleID: "com.microsoft.VSCode")),
            SnapLayoutSlot(id: "s2", region: .preset(.topRightQuarter), binding: .mostRecent),
            SnapLayoutSlot(id: "s3", region: .preset(.bottomRightQuarter), binding: .empty),
        ]),
    ]
    let data = try JSONEncoder().encode(cfg)
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: data)
    #expect(decoded == cfg)
    #expect(decoded.presets.first?.slots.map(\.binding) ==
            [.app(bundleID: "com.microsoft.VSCode"), .mostRecent, .empty])
}

/// A file written without any presets still decodes, with presets empty and the rest intact (no wipe).
@Test func fileWithoutPresetsGetsEmpty() throws {
    let oldJSON = #"{ "snap": { "enabled": false } }"#
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: Data(oldJSON.utf8))
    #expect(decoded.snap.enabled == false)
    #expect(decoded.presets.isEmpty)
}

/// A malformed slot inside a layout is dropped individually rather than throwing away the layout, or,
/// worse, failing the whole config decode (which would reset every setting).
@Test func malformedSlotIsDroppedNotFatal() throws {
    let json = """
    {
      "presets": [
        { "id": "L", "name": "Mixed", "slots": [
          { "id": "good", "region": "leftHalf", "binding": { "kind": "mostRecent" } },
          "this-is-not-a-slot",
          { "id": "badregion", "region": "nopeZone", "binding": { "kind": "empty" } }
        ] }
      ]
    }
    """
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: Data(json.utf8))
    let layout = try #require(decoded.presets.first)
    // The non-object element is dropped; the unknown-region slot survives, falling back to .maximize.
    #expect(layout.slots.map(\.id) == ["good", "badregion"])
    #expect(layout.slots[0].region == .preset(.leftHalf))
    #expect(layout.slots[1].region == .preset(.maximize))
}

/// An app binding missing its bundle id degrades to `.mostRecent` instead of throwing.
@Test func appBindingWithoutBundleIdDegrades() throws {
    let json = #"{ "presets": [ { "id": "L", "name": "x", "slots": [ { "id": "s", "region": "maximize", "binding": { "kind": "app" } } ] } ] }"#
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: Data(json.utf8))
    #expect(decoded.presets.first?.slots.first?.binding == .mostRecent)
}

@Test func gridAndLaunchFlagRoundTrip() throws {
    var cfg = MacsPaneConfig.default
    cfg.presets = [
        SnapLayout(name: "Custom", slots: [
            SnapLayoutSlot(region: .custom(NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)),
                           binding: .app(bundleID: "com.acme.app"), launchIfClosed: true),
        ], cols: 4, rows: 3),
    ]
    let data = try JSONEncoder().encode(cfg)
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: data)
    #expect(decoded == cfg)
    #expect(decoded.presets.first?.cols == 4)
    #expect(decoded.presets.first?.rows == 3)
    #expect(decoded.presets.first?.slots.first?.launchIfClosed == true)
}

/// A layout/slot written before grid + launch existed must still decode, defaulting cleanly (no wipe).
@Test func legacyLayoutWithoutGridOrLaunchDefaults() throws {
    let json = #"{ "presets": [ { "id": "L", "name": "Old", "slots": [ { "id": "s", "region": "leftHalf", "binding": { "kind": "mostRecent" } } ] } ] }"#
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: Data(json.utf8))
    let layout = try #require(decoded.presets.first)
    #expect(layout.cols == 3 && layout.rows == 3)
    #expect(layout.slots.first?.launchIfClosed == false)
}
