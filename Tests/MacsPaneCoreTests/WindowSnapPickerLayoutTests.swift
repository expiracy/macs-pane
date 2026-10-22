import Testing
import CoreGraphics
@testable import MacsPaneCore

private let tiles = WindowSnapPickerLayout.Tiles(size: CGSize(width: 112, height: 74), spacing: 8, wingDivider: 24)
private let notch = CGSize(width: 200, height: 32)
/// Five tiles and four gaps; two tiles, a gap and the seam region.
private let row: CGFloat = 5 * 112 + 4 * 8
private let wing: CGFloat = 2 * 112 + 8 + 24

private func layout(screen: CGFloat, tiles count: Int = 5, pairings: Int = 0) -> WindowSnapPickerLayout {
    WindowSnapPickerLayout(notchSize: notch, screenWidth: screen, tiles: tiles,
                           tileCount: count, suggestionCount: pairings)
}

@Test func pickerKeepsFullSizeTilesOnALaptopScreen() {
    let picker = layout(screen: 1512, pairings: 2)
    #expect(picker.rowScale == 1)
    // The row, its padding, and the wing.
    let expected: CGFloat = row + 72 + wing
    #expect(picker.pickerSize.width == expected)
    #expect(picker.wingWidth == wing)
}

@Test func pickerShrinksEvenlyRatherThanLeaveANarrowScreen() {
    let picker = layout(screen: 1100, pairings: 2)
    #expect(picker.rowScale < 1)
    // The wing shifts the shape left of centre, so the picker must fit with the wing on BOTH sides:
    // centred row + a wing either side fills exactly the screen less its margin.
    let centred = picker.pickerSize.width - picker.wingWidth
    let spanned = centred + 2 * picker.wingWidth
    let fits = 1100 - WindowSnapPickerLayout.screenMargin
    #expect(abs(spanned - fits) < 0.5)
}

@Test func pickerWithoutPairingsHasNoWing() {
    let picker = layout(screen: 1512)
    #expect(picker.wingWidth == 0)
    let expected: CGFloat = row + 72
    #expect(picker.pickerSize.width == expected)
}

@Test func shortRowStillOpensToTheMinimumWidth() {
    #expect(layout(screen: 1512, tiles: 1).pickerSize.width == WindowSnapPickerLayout.minWidth)
}

@Test func pickerHeightHoldsTheNotchAndOneRow() {
    let picker = layout(screen: 1512)
    let expected: CGFloat = 32 + 8 + 74 + 4 + 16 + 10 + 22 + 12
    #expect(picker.pickerSize.height == expected)
}

@Test func dragTargetIsAThirdOfTheScreenButNeverNarrowerThanTheNotch() {
    #expect(layout(screen: 1500).dragTargetSize == CGSize(width: 500, height: 32))
    #expect(layout(screen: 300).dragTargetSize == CGSize(width: 200, height: 32))
}
