import Foundation

/// The order the user dragged a list into: the menu's presets and layouts.
public enum ListOrder {
    /// `items` with the ids `order` names first, in that order, then the rest as they were. Ids that
    /// name nothing are skipped.
    public static func sorted<Item: Identifiable>(_ items: [Item], by order: [Item.ID]) -> [Item] {
        guard !order.isEmpty else { return items }
        let rank = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        func key(_ item: (offset: Int, element: Item)) -> (Int, Int) {
            (rank[item.element.id] ?? order.count + item.offset, item.offset)
        }
        return items.enumerated().sorted { key($0) < key($1) }.map(\.element)
    }

    /// Move the item at `source` so it ends up at `destination` (clamped to the list).
    public static func move<Item>(from source: Int, to destination: Int, in items: inout [Item]) {
        guard items.indices.contains(source) else { return }
        let item = items.remove(at: source)
        items.insert(item, at: min(max(destination, 0), items.count))
    }
}
