import Testing
import Foundation
@testable import MacsPaneCore

@Test func windowSnapDefaultsAreOptInWithSymmetricRegions() {
    let d = WindowSnapConfig()
    #expect(d.enabled == false)                                  // opt-in; also needs Accessibility permission
    #expect(d.regions == WindowSnapZoneEntry.defaultRegions)     // full catalog, symmetric set enabled
    // Default picker row: quarters · half · maximize (centre) · half · quarters.
    #expect(d.enabledZones == [.topLeftQuarter, .bottomLeftQuarter,
                               .leftHalf, .maximize, .rightHalf,
                               .topRightQuarter, .bottomRightQuarter])
    #expect(d.showFullScreenPreview == true)
    // MacsPane itself turns it on: snapping is what the app is for.
    #expect(MacsPaneConfig.default.snap.enabled == true)
}

@Test func windowSnapConfigRoundTrips() throws {
    var cfg = MacsPaneConfig.default
    cfg.snap.enabled = true
    cfg.snap.showFullScreenPreview = false
    cfg.snap.dragActivationDistance = 12
    // A non-default, *complete* region list (all catalog zones present): reorder + retoggle.
    cfg.snap.regions.reverse()
    cfg.snap.regions[0].enabled.toggle()

    let data = try JSONEncoder().encode(cfg)
    let decoded = try JSONDecoder().decode(MacsPaneConfig.self, from: data)
    #expect(decoded == cfg)
}

/// A Notch++ `notch` block written before window snapping existed still imports, with `windowSnap`
/// falling back to its default and the rest of the block intact.
@Test func oldNotchPlusPlusBlockWithoutWindowSnapGetsDefault() throws {
    let oldNotchJSON = """
    {
      "enabled": true,
      "hoverExpandDelayMs": 120,
      "collapseDelayMs": 250,
      "fileShelf": { "enabled": true, "copyOnDrop": false, "maxItems": 10 }
    }
    """
    let decoded = try JSONDecoder().decode(NotchPlusPlusWindowSettings.self, from: Data(oldNotchJSON.utf8))
    // The pre-existing fields survived …
    #expect(decoded.hoverExpandDelayMs == 120)
    // … and window snapping picked up its default region list.
    #expect(decoded.windowSnap == WindowSnapConfig())
    #expect(decoded.windowSnap.enabled == false)
    #expect(decoded.windowSnap.regions == WindowSnapZoneEntry.defaultRegions)
}

// MARK: - Legacy `zoneSet` preset → `regions` migration

/// A config written by the preset era named `zoneSet: "full"`. It must migrate to the equivalent
/// enabled zones, *in the old preset's picker order*, with the rest of the catalog present-but-off.
@Test func legacyFullZoneSetMigratesToRegions() throws {
    let json = #"{ "enabled": true, "zoneSet": "full" }"#
    let decoded = try JSONDecoder().decode(WindowSnapConfig.self, from: Data(json.utf8))
    #expect(decoded.enabled == true)
    #expect(decoded.regions.count == WindowSnapZone.allCases.count)   // catalog completed, rest disabled
    #expect(decoded.enabledZones == [.maximize,
                                     .leftHalf, .rightHalf,
                                     .leftThird, .centerThird, .rightThird,
                                     .topLeftQuarter, .topRightQuarter,
                                     .bottomLeftQuarter, .bottomRightQuarter])
}

@Test func legacyHalvesQuartersZoneSetMigratesToRegions() throws {
    let json = #"{ "enabled": false, "zoneSet": "halvesQuarters" }"#
    let decoded = try JSONDecoder().decode(WindowSnapConfig.self, from: Data(json.utf8))
    #expect(decoded.regions.count == WindowSnapZone.allCases.count)
    #expect(decoded.enabledZones == [.maximize,
                                     .leftHalf, .rightHalf,
                                     .topLeftQuarter, .topRightQuarter,
                                     .bottomLeftQuarter, .bottomRightQuarter])
}

/// Regression: a config naming a removed/unknown preset (e.g. the dropped `halvesMaximize`) must fall
/// back to the default region list rather than throw — a throw would reset the whole config and wipe
/// the user's other settings.
@Test func unknownZoneSetFallsBackToDefaultRegions() throws {
    let json = #"{ "enabled": true, "zoneSet": "halvesMaximize" }"#
    let decoded = try JSONDecoder().decode(WindowSnapConfig.self, from: Data(json.utf8))
    #expect(decoded.enabled == true)                              // the rest of the config survived
    #expect(decoded.regions == WindowSnapZoneEntry.defaultRegions)   // unknown preset → default, no throw
}

// MARK: - Resilient `regions` decoding

/// A `regions` array that omits some catalog zones (e.g. written by an older build before they were
/// added) gains the missing ones appended as disabled — so new regions surface without a migration.
@Test func partialRegionsListGetsMissingZonesAppendedDisabled() throws {
    let json = #"{ "enabled": true, "regions": [ {"zone":"maximize","enabled":true}, {"zone":"leftHalf","enabled":true} ] }"#
    let decoded = try JSONDecoder().decode(WindowSnapConfig.self, from: Data(json.utf8))
    #expect(decoded.regions.count == WindowSnapZone.allCases.count)        // 2 stored + the rest appended
    #expect(decoded.regions.prefix(2).map(\.zone) == [.maximize, .leftHalf])
    #expect(decoded.enabledZones == [.maximize, .leftHalf])               // only the two we enabled
    #expect(decoded.regions.dropFirst(2).allSatisfy { !$0.enabled })      // appended ones are off
}

/// An unknown/removed zone name inside `regions` is dropped (not thrown on), keeping the rest.
@Test func unknownZoneInRegionsIsDropped() throws {
    let json = #"{ "enabled": true, "regions": [ {"zone":"maximize","enabled":true}, {"zone":"bogusZone","enabled":true}, {"zone":"leftHalf","enabled":false} ] }"#
    let decoded = try JSONDecoder().decode(WindowSnapConfig.self, from: Data(json.utf8))
    #expect(decoded.regions.count == WindowSnapZone.allCases.count)        // bogus dropped, catalog completed
    #expect(decoded.regions.prefix(2).map(\.zone) == [.maximize, .leftHalf])  // bogus gone
    #expect(decoded.enabledZones == [.maximize])                          // leftHalf stored as disabled
}
