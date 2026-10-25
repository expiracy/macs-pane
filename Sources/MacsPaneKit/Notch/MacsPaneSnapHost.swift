#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// MacsPane's notch, which exists only for a window drag: hidden at rest, the widened drag target
/// while a window is dragged, and the snap picker once the drag rests on it. It is the
/// `WindowSnapHosting` the `WindowSnapController` drives.
///
/// The open timing is the notch's: the drag must *rest* (slower than `restSpeed`) for `dwellMs`, so
/// sliding a window along the menu bar never opens it, and leaving closes it after `collapseDelay`.
final class MacsPaneSnapHost: ObservableObject, WindowSnapHosting {
    enum Stage: Equatable { case rest, target, picker }

    @Published private(set) var stage: Stage = .rest
    /// The host screen's notch, set by `MacsPaneNotchController` when it places the panel.
    @Published var notchSize = NotchGeometry.standardNotchSize
    @Published var screenWidth: CGFloat = 1440
    @Published var hasRealNotch = true

    let windowSnap: WindowSnapViewModel
    let recents: RecentWindowsService
    let dragStrip = NotchDragStripModel()
    var dwellMs: Int
    /// A pairing was tiled from the picker: offer its Undo.
    var onPairingTiled: ((_ undo: @escaping WindowsUndo) -> Void)?
    /// A preset on the right island was the release target.
    var onPresetChosen: ((String, WindowUndoCapture.DraggedHome?) -> Void)?
    /// A window drag began: the notch is about to widen into the drag target.
    var onWindowDragStart: (() -> Void)?

    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var anchor: PointerSample?

    /// A pointer slower than this (points per second) is at rest.
    private static let restSpeed: CGFloat = 120
    private static let collapseDelay: TimeInterval = 0.25
    /// The most pairing tiles the picker shows; the panel is built wide enough for them up front.
    static let maxSuggestions = WindowSnapMetrics.maxSuggestions

    init(config: MacsPaneConfig, recents: RecentWindowsService) {
        self.windowSnap = WindowSnapViewModel(config: config.snap)
        self.recents = recents
        self.dwellMs = config.dwellMs
        windowSnap.apply(windowConfig: config.windows)
        windowSnap.apply(presets: config.presets)
    }

    func apply(_ config: MacsPaneConfig) {
        windowSnap.apply(config: config.snap)
        windowSnap.apply(windowConfig: config.windows)
        windowSnap.apply(presets: config.presets)
        dwellMs = config.dwellMs
    }

    // MARK: - Geometry

    static let tiles = WindowSnapPickerLayout.Tiles(size: WindowSnapMetrics.tileSize,
                                                    spacing: WindowSnapMetrics.tileSpacing,
                                                    islandGap: WindowSnapMetrics.islandGap,
                                                    islandPadding: WindowSnapMetrics.islandPadding)

    /// The picker's measures for this drag; pass counts to size for more (the panel is built for the
    /// most pairings and presets the islands can show, so it never needs resizing mid-drag).
    func layout(suggestions: Int? = nil, presets: Int? = nil) -> WindowSnapPickerLayout {
        WindowSnapPickerLayout(notchSize: notchSize, screenWidth: screenWidth, tiles: Self.tiles,
                               tileCount: windowSnap.pickerTileCount,
                               suggestionCount: suggestions ?? windowSnap.suggestions.count,
                               presetCount: presets ?? windowSnap.presets.count)
    }

    var rowScale: CGFloat { layout().rowScale }
    var isSnapPickerOpen: Bool { stage == .picker }
    var snapPickerSize: CGSize { layout().footprint }
    var windowDragTargetSize: CGSize { layout().dragTargetSize }

    /// What the black shape is drawn at now. At rest it is the hardware notch exactly (invisible on a
    /// notched Mac) or nothing at all on a screen without one, never a fake notch.
    var shapeSize: CGSize {
        switch stage {
        case .rest: hasRealNotch ? notchSize : CGSize(width: notchSize.width, height: 0)
        case .target: windowDragTargetSize
        case .picker: layout().pickerSize
        }
    }

    // MARK: - WindowSnapHosting

    func setWindowDragActive(_ active: Bool) {
        if active {
            guard stage == .rest else { return }
            onWindowDragStart?()
            withAnimation(NotchMotion.dragTarget) { stage = .target }
        } else {
            dragStrip.reset()
            guard stage == .target else { return }   // an open picker closes through `collapseSnapPicker`
            cancelPendingHoverTransitions()
            withAnimation(NotchMotion.dragTarget) { stage = .rest }
        }
    }

    func setWindowOnTarget(_ onTarget: Bool) { dragStrip.setWindowOnTarget(onTarget) }

    func setPointerInside(_ inside: Bool, at point: CGPoint?) {
        if inside {
            collapseWork?.cancel(); collapseWork = nil
            guard stage == .target else { return }
            let sample = point.map { PointerSample(point: $0, time: ProcessInfo.processInfo.systemUptime) }
            if expandWork == nil {
                anchor = sample
                scheduleExpand()
            } else if let sample, let last = anchor {
                anchor = sample
                // Still travelling: the rest starts again, so only a pause on the notch opens it.
                if sample.speed(since: last) > Self.restSpeed { scheduleExpand() }
            }
        } else {
            expandWork?.cancel(); expandWork = nil
            anchor = nil
            guard stage == .picker, collapseWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.collapseWork = nil
                self.windowSnap.clearHighlight()
                withAnimation(NotchMotion.close) { self.stage = .target }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseDelay, execute: work)
        }
    }

    func cancelPendingHoverTransitions() {
        expandWork?.cancel(); expandWork = nil
        collapseWork?.cancel(); collapseWork = nil
        anchor = nil
    }

    func collapseSnapPicker(completion: @escaping () -> Void) {
        cancelPendingHoverTransitions()
        withAnimation(NotchMotion.close, completionCriteria: .removed) {
            stage = .rest
        } completion: {
            completion()
        }
    }

    func offerPairingUndo(_ undo: @escaping WindowsUndo) { onPairingTiled?(undo) }

    func applyPreset(_ id: String, dragged: WindowUndoCapture.DraggedHome?) { onPresetChosen?(id, dragged) }

    private func scheduleExpand() {
        expandWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.stage == .target else { return }
            self.expandWork = nil
            self.anchor = nil
            withAnimation(NotchMotion.open) { self.stage = .picker }
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(dwellMs), execute: work)
    }
}
#endif
