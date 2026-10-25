import Testing
import CoreGraphics
@testable import MacsPaneCore

private let tiles = WindowSnapPickerLayout.Tiles(size: CGSize(width: 88, height: 58), spacing: 8,
                                                 islandGap: 14, islandPadding: 14)
private let notch = CGSize(width: 200, height: 32)
/// Four tiles and three gaps.
private let row: CGFloat = 4 * 88 + 3 * 8

private func layout(screen: CGFloat, tiles count: Int = 4, pairings: Int = 0,
                    presets: Int = 0) -> WindowSnapPickerLayout {
    WindowSnapPickerLayout(notchSize: notch, screenWidth: screen, tiles: tiles,
                           tileCount: count, suggestionCount: pairings, presetCount: presets)
}

@Test func theNotchHugsItsLayoutRow() {
    let picker = layout(screen: 1512)
    #expect(picker.rowScale == 1)
    #expect(picker.pickerSize.width == row + 2 * WindowSnapPickerLayout.rowInset)
    #expect(picker.footprint.width == picker.pickerSize.width)
}

@Test func aShortRowStillClearsTheCamera() {
    let picker = layout(screen: 1512, tiles: 1)
    #expect(picker.pickerSize.width == 200 + WindowSnapPickerLayout.cameraClearance)
}

@Test func eachIslandFitsItsOwnTiles() {
    let picker = layout(screen: 1512, pairings: 2, presets: 3)
    let pair: CGFloat = 2 * 88 + 8 + 28
    let trio: CGFloat = 3 * 88 + 2 * 8 + 28
    #expect(picker.leftIslandSize.width == pair)
    #expect(picker.rightIslandSize.width == trio)
    #expect(picker.leftIslandSize.height == picker.rightIslandSize.height)
    #expect(layout(screen: 1512, presets: 3).leftIslandSize == .zero)
}

@Test func theFootprintKeepsTheNotchCentredBetweenUnevenIslands() {
    let picker = layout(screen: 1512, pairings: 2, presets: 3)
    // The wider island is budgeted on both sides, so the notch stays under the camera.
    #expect(picker.footprint.width == picker.pickerSize.width + 2 * (14 + picker.rightIslandSize.width))
}

@Test func aNarrowScreenShrinksEverythingEvenlyToFit() {
    let picker = layout(screen: 900, pairings: 2, presets: 4)
    #expect(picker.rowScale < 1)
    #expect(abs(picker.footprint.width - (900 - WindowSnapPickerLayout.screenMargin)) < 0.5)
}

@Test func heightsHoldTheNotchTheRowAndTheIslands() {
    let picker = layout(screen: 1512, pairings: 2)
    // Notch: the camera row (its title sits beside the camera), the tiles, their names, the curve.
    let notchHeight: CGFloat = 32 + 10 + 58 + 4 + 16 + 14
    // Island: a heading, the tiles and their names.
    let islandHeight: CGFloat = 10 + 22 + 58 + 4 + 16 + 10
    #expect(picker.pickerSize.height == notchHeight)
    #expect(picker.leftIslandSize.height == islandHeight)
    // The islands rise into the menu bar, as far from the top of the screen as from the notch.
    #expect(picker.islandTop == 14)
    // The notch's tiles start just under the camera row; an island's heading just inside its top.
    #expect(picker.rowTop == 42)
    #expect(picker.islandContentTop == picker.islandTop + 10)
    #expect(picker.footprint.height == max(picker.pickerSize.height, picker.islandTop + picker.leftIslandSize.height))
}

@Test func theDragTargetIsAsWideAsTheOpenNotchSoOpeningOnlyGrowsDown() {
    let picker = layout(screen: 1512, pairings: 2, presets: 3)
    #expect(picker.dragTargetSize == CGSize(width: picker.pickerSize.width, height: 32))
    #expect(layout(screen: 1512, tiles: 1).dragTargetSize.width == 200 + WindowSnapPickerLayout.cameraClearance)
}
