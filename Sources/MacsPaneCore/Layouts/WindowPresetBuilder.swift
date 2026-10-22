import Foundation

/// Converts empty layout boxes into an app-fillable preset without changing their geometry.
public enum WindowPresetBuilder {
    /// Every box's layer in a preset: the stored one, else the draw-order rule. Left-out boxes get none.
    public static func layers(of preset: SnapLayout) -> [Int?] {
        let excluded = Set(preset.slots.indices.filter { preset.slots[$0].isRemoved })
        return WindowBoxLayers.resolve(preset.slots.map(\.region.unitRect),
                                       stored: preset.slots.map(\.layer), excluded: excluded)
    }

    /// Put one of a preset's boxes on another layer; every other box keeps the layer it has now.
    public static func setLayer(_ layer: Int, ofBox index: Int, in preset: inout SnapLayout) {
        guard preset.slots.indices.contains(index) else { return }
        let current = layers(of: preset)
        for slot in preset.slots.indices { preset.slots[slot].layer = current[slot] }
        preset.slots[index].layer = max(0, layer)
    }

    public static func make(from layout: WindowLayout, name: String, profileID: String? = nil) -> SnapLayout {
        let layers = layout.layers
        let slots = layout.boxes.enumerated().map { index, box in
            SnapLayoutSlot(region: box, binding: .empty, layer: layers[index])
        }
        return SnapLayout(name: name, slots: slots, profileID: profileID, layoutID: layout.id)
    }

    public static func assign(bundleID: String, toBox index: Int, in preset: inout SnapLayout) {
        guard preset.slots.indices.contains(index), !bundleID.isEmpty else { return }
        preset.slots[index].binding = .app(bundleID: bundleID)
        preset.slots[index].isRemoved = false
    }

    /// A name is not required: an untyped one saves as the next "Preset n".
    public static func canSave(_ preset: SnapLayout, isNew: Bool) -> Bool {
        guard isNew else { return true }
        return preset.slots.contains { slot in
            guard !slot.isRemoved else { return false }
            return slot.binding != .empty
        }
    }
}
