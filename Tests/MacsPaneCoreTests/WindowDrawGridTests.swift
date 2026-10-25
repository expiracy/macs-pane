import CoreGraphics
import Testing
@testable import MacsPaneCore

@Test func aDrawnBoxStaysInsideTheDisplay() {
    let rect = WindowDrawGrid.rect(from: CGPoint(x: 0.8, y: -0.2), to: CGPoint(x: 1.4, y: 0.5), grid: false)
    #expect(abs(rect.minX - 0.8) < 0.0001 && rect.minY == 0)
    #expect(abs(rect.maxX - 1) < 0.0001 && abs(rect.height - 0.5) < 0.0001)
}

@Test func theGridLandsEdgesOnTheLatticeAndKeepsAtLeastOneCell() {
    let rect = WindowDrawGrid.rect(from: CGPoint(x: 0.01, y: 0.02), to: CGPoint(x: 0.49, y: 0.51), grid: true)
    #expect(abs(rect.minX) < 0.0001)
    #expect(abs(rect.width - 0.5) < 0.0001)
    #expect(abs(rect.height - 8.0 / 15) < 0.0001)
    let tiny = WindowDrawGrid.rect(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.505, y: 0.505), grid: true)
    #expect(abs(tiny.width - 1.0 / 24) < 0.0001)
    #expect(abs(tiny.height - 1.0 / 15) < 0.0001)
}

@Test func aMovedBoxIsKeptWholeInsideTheDisplay() {
    let box = CGRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4)
    let moved = WindowDrawGrid.moved(box, by: CGSize(width: 0.5, height: -0.9), grid: false)
    #expect(moved == CGRect(x: 0.6, y: 0, width: 0.4, height: 0.4))
}

@Test func aResizedBoxStopsAtTheEdgeAndAtItsMinimum() {
    let box = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
    let grown = WindowDrawGrid.resized(box, by: CGSize(width: 1, height: 1), grid: false)
    #expect(grown.maxX == 1 && grown.maxY == 1)
    let shrunk = WindowDrawGrid.resized(box, by: CGSize(width: -1, height: -1), grid: false)
    #expect(shrunk.width == 0.03 && shrunk.height == 0.03)
}

@Test func installedAppsSkipTheRunningOnesAndDuplicates() {
    let apps = [InstalledApp(bundleID: "b", name: "Zed", path: "/A/Zed.app"),
                InstalledApp(bundleID: "a", name: "notes", path: "/A/Notes.app"),
                InstalledApp(bundleID: "b", name: "Zed", path: "/B/Zed.app"),
                InstalledApp(bundleID: "c", name: "Safari", path: "/A/Safari.app")]
    #expect(InstalledAppCatalog.notRunning(apps, running: ["c"]).map(\.bundleID) == ["a", "b"])
}

@Suite struct WindowBoxEditTests {
    @Test func edgesFindTheSideOrCornerUnderThePointer() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        #expect(WindowDrawGrid.edges(at: CGPoint(x: 200, y: 150), in: rect, tolerance: 6).isEmpty)
        #expect(WindowDrawGrid.edges(at: CGPoint(x: 102, y: 150), in: rect, tolerance: 6) == .left)
        #expect(WindowDrawGrid.edges(at: CGPoint(x: 298, y: 198), in: rect, tolerance: 6) == [.right, .bottom])
        #expect(WindowDrawGrid.edges(at: CGPoint(x: 400, y: 150), in: rect, tolerance: 6).isEmpty)
    }

    @Test func resizingAnEdgeKeepsTheOthersAndStaysInside() {
        let rect = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let left = WindowDrawGrid.resized(rect, edges: .left, by: CGSize(width: -0.5, height: 0), grid: false)
        #expect(left.minX == 0)
        #expect(abs(left.maxX - 0.6) < 0.0001)
        let top = WindowDrawGrid.resized(rect, edges: .top, by: CGSize(width: 0, height: 0.9), grid: false)
        #expect(abs(top.maxY - 0.6) < 0.0001)
        #expect(top.height >= 0.03)
    }

    @Test func aBoxCanBeMovedToAnotherLayer() {
        var layout = WindowLayout(name: "L", boxes: [
            .custom(NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)),
            .custom(NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1))
        ])
        layout.setLayer(1, ofBox: 0)
        #expect(layout.layers == [1, 0])
        #expect(WindowBoxLayers.deepestChoice(layout.layers.map { Optional($0) }) == 2)
        var preset = WindowPresetBuilder.make(from: layout, name: "P")
        WindowPresetBuilder.setLayer(0, ofBox: 0, in: &preset)
        #expect(WindowPresetBuilder.layers(of: preset) == [0, 0])
    }
}
