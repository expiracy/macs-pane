#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// The editor's picture: the whole screen dimmed, the boxes drawn at full size over its visible area
/// (the menu bar and Dock excluded, as windows are), a toolbar floating at the top and one line of help
/// at the bottom. A box is the size its window will be.
struct BoxEditorView: View {
    @ObservedObject var model: BoxEditorModel
    let screenFrame: CGRect
    let visibleFrame: CGRect

    /// The visible frame in the view's own top-left space.
    private var desk: CGRect {
        CGRect(x: visibleFrame.minX - screenFrame.minX, y: screenFrame.maxY - visibleFrame.maxY,
               width: visibleFrame.width, height: visibleFrame.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            // The drawing is always dark glass over the dimmed screen, whatever the system appearance,
            // so white labels read on every wallpaper.
            BoxEditorDesk(model: model, size: desk.size)
                .environment(\.colorScheme, .dark)
                .frame(width: desk.width, height: desk.height)
                .offset(x: desk.minX, y: desk.minY)
            // The grid switch hangs just under the toolbar, where it is seen before the first box is drawn.
            VStack(spacing: 8) {
                BoxEditorToolbar(model: model)
                    .fixedSize()
                gridSwitch
            }
            .frame(width: desk.width)
            .offset(x: desk.minX, y: desk.minY + 14)
            hint
                .frame(width: desk.width)
                .offset(x: desk.minX, y: desk.maxY - 50)
        }
        .frame(width: screenFrame.width, height: screenFrame.height, alignment: .topLeading)
    }

    /// One line of help at the bottom: what to do next. Solid, like the bars at the top, in a dark
    /// colour of its own so it reads as help rather than as a control.
    private var hint: some View {
        Text(model.hint)
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background {
                Capsule().fill(Color(white: 0.14))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            }
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.15), value: model.hint)
    }

    /// The drawing settings: a smaller bar in the toolbar's own colour, hanging just under it. Today it
    /// holds the grid switch.
    private var gridSwitch: some View {
        Toggle(isOn: $model.grid) {
            Label("Snap to grid", systemImage: "grid")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.callout)
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .fixedSize()
        .help("Line box edges up on a grid as you draw, move and resize")
    }
}

/// Where boxes are drawn: drag on empty space draws one, drag a box to move it, drag near its edge to
/// resize it, click empty space to drop the selection.
private struct BoxEditorDesk: View {
    @ObservedObject var model: BoxEditorModel
    let size: CGSize
    static let space = "boxEditorDesk"

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white.opacity(0.001)
                .contentShape(Rectangle())
                .gesture(drawGesture)
                .onContinuousHover { phase in
                    if case .active = phase { NSCursor.crosshair.set() } else { NSCursor.arrow.set() }
                }
            if model.grid { gridLines.allowsHitTesting(false) }
            ForEach(model.draft.paintOrder) { box in
                // A hair inside its true frame, so two boxes that share an edge read as two.
                let rect = points(box.rect).insetBy(dx: 3, dy: 3)
                BoxEditorBox(model: model, box: box, frame: rect, deskSize: size)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            if let drawing = model.drawing {
                let rect = points(drawing)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
                    .overlay { sizeLabel(drawing).allowsHitTesting(false) }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
    }

    private func points(_ unit: CGRect) -> CGRect {
        CGRect(x: unit.minX * size.width, y: unit.minY * size.height,
               width: unit.width * size.width, height: unit.height * size.height)
    }

    private func unit(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / size.width, y: point.y / size.height)
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                model.select(nil)
                model.drawing = WindowDrawGrid.rect(from: unit(value.startLocation), to: unit(value.location),
                                                    grid: model.grid)
            }
            .onEnded { value in
                model.drawing = nil
                model.draft.draw(from: unit(value.startLocation), to: unit(value.location), grid: model.grid)
            }
    }

    private func sizeLabel(_ unit: CGRect) -> some View {
        Text("\(Int((unit.width * 100).rounded()))% × \(Int((unit.height * 100).rounded()))%")
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(0.45)))
    }

    private var gridLines: some View {
        Canvas { context, size in
            var path = Path()
            for column in 1..<WindowDrawGrid.columns {
                let x = size.width * CGFloat(column) / CGFloat(WindowDrawGrid.columns)
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 1..<WindowDrawGrid.rows {
                let y = size.height * CGFloat(row) / CGFloat(WindowDrawGrid.rows)
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 1)
        }
    }
}

/// One box at full size: its number, its size, and in a preset the app that opens there. Drag it to
/// move it, drag near an edge or corner to resize it; the selected one shows its handles and a remove
/// button.
private struct BoxEditorBox: View {
    @ObservedObject var model: BoxEditorModel
    let box: WindowBoxDraft.Box
    /// Where the box sits on the desk, in points.
    let frame: CGRect
    let deskSize: CGSize
    @State private var grab: (start: CGRect, edges: WindowDrawGrid.Edges)?
    @State private var hovered = false

    private static let edgeTolerance: CGFloat = 12
    private var selected: Bool { model.draft.selection == box.id }
    private var number: Int { (model.draft.boxes.firstIndex { $0.id == box.id } ?? 0) + 1 }
    private var compact: Bool { frame.width < 170 || frame.height < 130 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            // Only the box's own glass casts the shadow, never the buttons and labels drawn on it.
            shape.fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(selected ? 0.35 : 0.2), radius: selected ? 14 : 6, y: 3)
            shape.fill(Color.accentColor.opacity(selected ? 0.30 : hovered ? 0.24 : 0.18))
            shape.strokeBorder(Color.accentColor.opacity(selected ? 1 : 0.8), lineWidth: selected ? 3 : 1.5)
            content
                .padding(10)
        }
        .overlay(alignment: .topLeading) { badge }
        .overlay(alignment: .topTrailing) { if selected || hovered { removeButton } }
        .overlay { if selected { handles } }
        .contentShape(shape)
        .onHover { hovered = $0 }
        .onContinuousHover { phase in
            guard case .active(let location) = phase else { NSCursor.arrow.set(); return }
            cursor(for: WindowDrawGrid.edges(at: location, in: CGRect(origin: .zero, size: frame.size),
                                             tolerance: Self.edgeTolerance)).set()
        }
        .gesture(dragGesture)
        .simultaneousGesture(TapGesture().onEnded { model.select(box.id) })
        .animation(.easeOut(duration: 0.12), value: selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Box \(number)")
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: compact ? 4 : 10) {
            if model.draft.kind == .preset { BoxAppButton(model: model, box: box, compact: compact) }
            if !compact || model.draft.kind == .layout {
                Text("\(Int((box.rect.width * 100).rounded()))% × \(Int((box.rect.height * 100).rounded()))%")
                    .font((model.draft.kind == .layout ? Font.title3 : .caption).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(model.draft.kind == .layout ? 0.95 : 0.7))
            }
        }
    }

    private var badge: some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.accentColor))
            .padding(8)
            .allowsHitTesting(false)
    }

    private var removeButton: some View {
        Button { model.draft.remove(box.id) } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(7)
        .help("Remove this box")
        .accessibilityLabel("Remove box \(number)")
    }

    /// Corner dots on the selected box, to say its edges can be pulled.
    private var handles: some View {
        GeometryReader { geo in
            ForEach(0..<4, id: \.self) { corner in
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                    .frame(width: 11, height: 11)
                    .position(x: corner % 2 == 0 ? 0 : geo.size.width, y: corner < 2 ? 0 : geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(BoxEditorDesk.space))
            .onChanged { value in
                let grab = self.grab ?? {
                    let local = CGPoint(x: value.startLocation.x - frame.minX, y: value.startLocation.y - frame.minY)
                    let edges = WindowDrawGrid.edges(at: local, in: CGRect(origin: .zero, size: frame.size),
                                                     tolerance: Self.edgeTolerance)
                    model.select(box.id)
                    return (box.rect, edges)
                }()
                self.grab = grab
                let delta = CGSize(width: value.translation.width / deskSize.width,
                                   height: value.translation.height / deskSize.height)
                if grab.edges.isEmpty {
                    model.draft.move(box.id, from: grab.start, by: delta, grid: model.grid)
                } else {
                    model.draft.resize(box.id, from: grab.start, edges: grab.edges, by: delta, grid: model.grid)
                }
            }
            .onEnded { _ in grab = nil }
    }

    private func cursor(for edges: WindowDrawGrid.Edges) -> NSCursor {
        if edges.isEmpty { return grab == nil ? .openHand : .closedHand }
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch (edges.contains(.top), edges.contains(.bottom), edges.contains(.left), edges.contains(.right)) {
            case (true, _, true, _): position = .topLeft
            case (true, _, _, true): position = .topRight
            case (_, true, true, _): position = .bottomLeft
            case (_, true, _, true): position = .bottomRight
            case (true, _, _, _): position = .top
            case (_, true, _, _): position = .bottom
            case (_, _, true, _): position = .left
            default: position = .right
            }
            return .frameResize(position: position, directions: .all)
        }
        if edges.contains(.left) || edges.contains(.right) {
            return edges.contains(.top) || edges.contains(.bottom) ? .crosshair : .resizeLeftRight
        }
        return .resizeUpDown
    }
}

/// A preset box's app: its icon and name, "Any recent window", or a prompt to choose one. Opens the
/// app picker.
private struct BoxAppButton: View {
    @ObservedObject var model: BoxEditorModel
    let box: WindowBoxDraft.Box
    let compact: Bool

    private var isPicking: Binding<Bool> {
        Binding(get: { model.pickingAppFor == box.id },
                set: { model.pickingAppFor = $0 ? box.id : (model.pickingAppFor == box.id ? nil : model.pickingAppFor) })
    }

    var body: some View {
        VStack(spacing: 6) {
            Button { model.select(box.id); model.pickingAppFor = box.id } label: { label }
                .buttonStyle(.plain)
                .help("Choose what opens in this box")
                .popover(isPresented: isPicking, arrowEdge: .bottom) {
                    BoxAppPicker(model: model, boxID: box.id)
                }
            if !compact, case .app = box.binding {
                Toggle("Open it if it's closed", isOn: Binding(
                    get: { box.launchIfClosed },
                    set: { model.draft.setLaunchIfClosed($0, for: box.id) }))
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder private var label: some View {
        switch box.binding {
        case .app(let bundleID):
            VStack(spacing: 6) {
                if let icon = model.appIcon(bundleID) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: compact ? 32 : 56, height: compact ? 32 : 56)
                }
                if !compact {
                    Text(model.appName(bundleID))
                        .font(.headline).foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .padding(6)
            .contentShape(Rectangle())
        case .mostRecent:
            chip("clock.arrow.circlepath", compact ? nil : "Any recent window")
        case .empty:
            chip("plus.app", compact ? nil : "Choose an app")
        }
    }

    private func chip(_ symbol: String, _ title: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            if let title { Text(title) }
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Color.accentColor))
        .contentShape(Capsule())
    }
}

#endif
