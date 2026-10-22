import Foundation

/// Edits the ordered set of layouts the drag-to-top bar offers — as many as you like; the picker's row
/// grows with them. Every caller goes through here so the duplicate rule and the prune-on-delete rule
/// are stated once.
public enum WindowDragBarEditor {
    public enum ToggleResult: Equatable, Sendable {
        /// The layout is now offered in the bar.
        case offered
        /// The layout was taken out of the bar.
        case takenOut
        /// The id names no layout in the catalog; nothing changed.
        case unknown
        /// The bar already offers this layout; nothing changed.
        case alreadyOffered
    }

    /// Put a layout in the bar, or take it out if it is already there.
    public static func toggle(_ id: String, in ids: inout [String],
                              catalog: [WindowLayout]) -> ToggleResult {
        guard catalog.contains(where: { $0.id == id }) else { return .unknown }
        if ids.contains(id) {
            ids.removeAll { $0 == id }
            return .takenOut
        }
        ids.append(id)
        return .offered
    }

    /// Insert a layout at a position in the bar — the drop of a layout tile onto the island.
    @discardableResult
    public static func insert(_ id: String, at index: Int, in ids: inout [String],
                              catalog: [WindowLayout]) -> ToggleResult {
        guard catalog.contains(where: { $0.id == id }) else { return .unknown }
        guard !ids.contains(id) else { return .alreadyOffered }
        ids.insert(id, at: min(max(index, 0), ids.count))
        return .offered
    }

    public static func remove(_ id: String, from ids: inout [String]) {
        ids.removeAll { $0 == id }
    }

    /// Reorder the bar. `destination` is the index the tile is dropped onto.
    public static func move(from source: Int, to destination: Int, in ids: inout [String]) {
        guard ids.indices.contains(source), source != destination else { return }
        let id = ids.remove(at: source)
        ids.insert(id, at: min(max(destination, 0), ids.count))
    }

    /// Drop ids whose layout no longer exists, and duplicates.
    public static func pruned(_ ids: [String], catalog: [WindowLayout]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { id in
            guard catalog.contains(where: { $0.id == id }) else { return false }
            return seen.insert(id).inserted
        }
    }
}
