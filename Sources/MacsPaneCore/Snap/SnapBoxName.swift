import CoreGraphics

/// A box of a layout in words, for the picker's caption while the pointer is on it: "Left half",
/// "Top left quarter", "Middle third", or where it sits when it has no common size ("Left side",
/// "Top right", "Centre").
public enum SnapBoxName {
    /// `unit` is an AppKit unit rect: origin bottom-left, y counting up.
    public static func describe(_ unit: CGRect) -> String {
        let fullWidth = near(unit.width, 1), fullHeight = near(unit.height, 1)
        if fullWidth && fullHeight { return "Full screen" }
        let across = fullWidth ? nil : near(unit.minX, 0) ? "left" : near(unit.maxX, 1) ? "right" : "middle"
        let down = fullHeight ? nil : near(unit.maxY, 1) ? "top" : near(unit.minY, 0) ? "bottom" : "middle"
        if across == "middle" && down == "middle" { return "Centre" }
        let place = [down, across].compactMap { $0 }.joined(separator: " ")
        if let size = size(unit, fullWidth: fullWidth, fullHeight: fullHeight) {
            return capitalised("\(place) \(size)")
        }
        return capitalised([down, across].compactMap { $0 }.count == 1 ? "\(place) side" : place)
    }

    /// The common fraction a box covers: a half, third or two thirds of a column or row, or a quarter.
    private static func size(_ unit: CGRect, fullWidth: Bool, fullHeight: Bool) -> String? {
        if near(unit.width, 0.5) && near(unit.height, 0.5) { return "quarter" }
        let span = fullHeight ? unit.width : fullWidth ? unit.height : nil
        guard let span else { return nil }
        if near(span, 0.5) { return "half" }
        if near(span, 1.0 / 3) { return "third" }
        if near(span, 2.0 / 3) { return "two thirds" }
        if near(span, 0.25) { return "quarter" }
        return nil
    }

    private static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.02 }

    private static func capitalised(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
}
