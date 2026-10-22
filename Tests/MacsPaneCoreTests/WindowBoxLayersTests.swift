import CoreGraphics
import Foundation
import Testing
@testable import MacsPaneCore

private func region(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> SnapRegion {
    .custom(NormalizedRect(x: x, y: y, width: w, height: h))
}

@Test func boxesThatOnlyTouchShareOneLayer() {
    let halves = WindowLayout.builtIns.first { $0.id == "halves" }!
    #expect(halves.layers == [0, 0])
    let quarters = WindowLayout.builtIns.first { $0.id == "quarters" }!
    #expect(WindowBoxLayers.count(quarters.layers.map { Optional($0) }) == 1)
}

@Test func aBoxDrawnOverAnotherGoesInTheLayerBelowIt() {
    var layout = WindowLayout(name: "", boxes: [])
    layout.appendBox(region(0.05, 0.1, 0.6, 0.8))
    layout.appendBox(region(0.4, 0.2, 0.55, 0.6))   // over box 1
    layout.appendBox(region(0.8, 0.85, 0.1, 0.1))   // over nothing
    #expect(layout.boxLayers == [0, 1, 0])
    layout.appendBox(region(0.5, 0.3, 0.1, 0.1))    // over boxes 1 and 2 → below the deeper one
    #expect(layout.boxLayers.last == 2)
}

@Test func removingABoxTakesItsLayerWithIt() {
    var layout = WindowLayout(name: "", boxes: [])
    layout.appendBox(region(0, 0, 0.6, 1))
    layout.appendBox(region(0.4, 0.2, 0.4, 0.5))
    layout.appendBox(region(0.7, 0.7, 0.2, 0.2))
    layout.removeBox(at: 0)
    #expect(layout.boxes.count == 2)
    #expect(layout.boxLayers == [1, 0])
}

@Test func aLayoutSavedBeforeLayersDecodesAndTakesTheDrawOrderRule() throws {
    let original = WindowLayout(id: "a", name: "Old", boxes: [region(0, 0, 0.6, 1), region(0.4, 0.2, 0.4, 0.5)])
    let encoded = try JSONEncoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "boxLayers")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(WindowLayout.self, from: legacy)
    #expect(decoded.boxLayers.isEmpty)
    #expect(decoded.layers == [0, 1])
}

@Test func aPresetCarriesItsLayoutsLayersAndLeftOutBoxesHaveNone() {
    var layout = WindowLayout(name: "", boxes: [])
    layout.appendBox(region(0, 0, 0.6, 1))
    layout.appendBox(region(0.4, 0.2, 0.4, 0.5))
    var preset = WindowPresetBuilder.make(from: layout, name: "")
    #expect(preset.slots.map(\.layer) == [0, 1])
    preset.slots[1].isRemoved = true
    #expect(WindowPresetBuilder.layers(of: preset) == [0, nil])
}

@Test func aPresetSlotSavedBeforeLayersDecodesWithNoLayer() throws {
    let slot = SnapLayoutSlot(region: region(0, 0, 1, 1), binding: .empty, layer: 2)
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(slot)) as? [String: Any])
    #expect(object["layer"] as? Int == 2)
    object.removeValue(forKey: "layer")
    let decoded = try JSONDecoder().decode(SnapLayoutSlot.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.layer == nil)
}

@Test func hidingALayerIsAViewAndCountsStayTrue() {
    let layers: [Int?] = [0, 1, 1, nil]
    #expect(WindowBoxLayers.count(layers) == 2)
    #expect(WindowBoxLayers.boxCounts(layers) == [1, 2])
    #expect(!WindowBoxLayers.isDrawn(1, hidden: [1]))
    #expect(WindowBoxLayers.isDrawn(0, hidden: [1]))
}

@Test func untypedNamesTakeTheNextFreeNumber() {
    #expect(WindowDefaultName.next("Preset", taken: []) == "Preset 1")
    #expect(WindowDefaultName.next("Preset", taken: ["Preset 1", "Morning", "Preset 3"]) == "Preset 2")
    #expect(WindowDefaultName.resolve("  ", word: "Layout", taken: ["Layout 1"]) == "Layout 2")
    #expect(WindowDefaultName.resolve(" Deep work ", word: "Layout", taken: []) == "Deep work")
}
