#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// The editor's floating toolbar: what is being drawn and its name, the layout it starts from (a preset)
/// or copies (a layout), a layout's place in the drag picker, which layers show (once boxes overlap),
/// snapping to the grid, then Delete (for a saved one), Cancel and Save.
struct BoxEditorToolbar: View {
    @ObservedObject var model: BoxEditorModel
    @State private var showingLayers = false

    var body: some View {
        HStack(spacing: 12) {
            Label(model.title, systemImage: model.draft.kind == .preset ? "square.grid.2x2" : "rectangle.dashed")
                .font(.headline)
                .labelStyle(.titleAndIcon)
                .fixedSize()
            TextField(model.defaultName, text: $model.draft.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
                .accessibilityLabel("Name")
            separator
            sourceMenu
            if model.draft.kind == .layout {
                Toggle("In the drag picker", isOn: $model.offeredInPicker)
                    .toggleStyle(.checkbox)
                    .help("Offer this layout when you drag a window to the notch")
            }
            if model.draft.layersInUse.count > 1 {
                separator
                layersButton
            }
            separator
            // A drawing aid, not part of what is saved: its own section, as a switch.
            Toggle("Snap to grid", isOn: $model.grid)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Line box edges up on a grid as you draw, move and resize")
            separator
            if !model.draft.isNew { deleteButton }
            Button("Cancel", action: model.cancel)
                .keyboardShortcut(.cancelAction)
            Button("Save", action: model.save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.draft.canSave)
                .help(model.draft.canSave ? "Save this \(model.noun)"
                      : model.draft.kind == .preset ? "Put an app in at least one box first" : "Draw a box first")
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // A solid bar, and only the bar casts the shadow: the buttons on it stay crisp.
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    private var separator: some View {
        Divider().frame(height: 22)
    }

    /// Opens the layers list; says how many show while some are hidden.
    private var layersButton: some View {
        let count = model.draft.layersInUse.count
        let hidden = model.hiddenLayers.count
        return Button { showingLayers.toggle() } label: {
            Label(hidden == 0 ? "Layers" : "Layers · \(count - hidden) of \(count)", systemImage: "square.3.layers.3d")
                .foregroundStyle(hidden == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
        }
        .help("Choose which layers show while you draw")
        .popover(isPresented: $showingLayers, arrowEdge: .bottom) { BoxLayersMenu(model: model) }
    }

    /// Fills the drawing with boxes that already exist. A preset starts from a layout (or from your
    /// windows, apps and all) and then gets its apps; a layout copies another layout's boxes.
    private var sourceMenu: some View {
        let preset = model.draft.kind == .preset
        return Menu {
            Button(preset ? "Your windows as they are now" : "The windows on this screen") {
                model.start(from: .windows)
            }
            Section("Layouts") {
                ForEach(model.startLayouts) { layout in
                    Button(layout.name) { model.start(from: .layout(layout)) }
                }
            }
            Divider()
            Button("Clear all boxes") { model.start(from: .empty) }
                .disabled(model.draft.boxes.isEmpty)
        } label: {
            Label(model.sourceMenuTitle, systemImage: preset ? "rectangle.split.2x1" : "square.on.square")
        }
        .fixedSize()
        .help(preset ? "Start this preset from a layout's boxes, or from your windows and their apps"
                     : "Replace the boxes with a copy of another layout's, or of the windows on this screen")
    }

    /// The bin, as in the menu: clicked once it grows into a red "bin ?", and a second click deletes.
    @ViewBuilder private var deleteButton: some View {
        let asking = model.confirmingDelete
        Group {
            if asking {
                Button { model.delete() } label: {
                    HStack(spacing: 1) {
                        Image(systemName: "trash")
                        Text("?").fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("Click again to delete this \(model.noun) for good")
                .accessibilityLabel("Confirm delete \(model.noun)")
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            } else {
                Button { withAnimation(.bouncy(duration: 0.3, extraBounce: 0.15)) { model.delete() } } label: {
                    Image(systemName: "trash")
                }
                .help("Delete this \(model.noun)")
                .accessibilityLabel("Delete \(model.noun)")
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .animation(.bouncy(duration: 0.3, extraBounce: 0.15), value: asking)
    }
}

/// The toolbar's layers: each one ticked to show it or not, with a small picture of its boxes (and
/// their apps, in a preset) and what is on it. Front first.
struct BoxLayersMenu: View {
    @ObservedObject var model: BoxEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Show").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 2)
            ForEach(model.draft.layersInUse, id: \.self) { layer in
                BoxLayerRow(model: model, layer: layer)
            }
            Divider().padding(.vertical, 4)
            Button("Show all layers") { model.showAllLayers() }
                .buttonStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .disabled(model.hiddenLayers.isEmpty)
                .foregroundStyle(model.hiddenLayers.isEmpty ? .secondary : .primary)
        }
        .padding(8)
        .frame(width: 300)
    }
}

private struct BoxLayerRow: View {
    @ObservedObject var model: BoxEditorModel
    let layer: Int
    @State private var hovered = false

    private var boxes: [WindowBoxDraft.Box] { model.boxes(onLayer: layer) }
    private var shown: Bool { !model.hiddenLayers.contains(layer) }

    var body: some View {
        Button { model.setLayer(layer, shown: !shown) } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(shown ? 1 : 0)
                    .frame(width: 14)
                MacsPaneLayoutGlyph(boxes: boxes.map { WindowBoxDraft.region($0.rect) },
                                    size: CGSize(width: 56, height: 35), icons: boxes.map(icon))
                    .opacity(shown ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.callout.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(hovered ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityValue(shown ? "Shown" : "Hidden")
    }

    private var name: String {
        let used = model.draft.layersInUse
        guard used.count > 1 else { return "Layer \(layer + 1)" }
        return "Layer \(layer + 1)" + (layer == used.first ? " · front" : layer == used.last ? " · back" : "")
    }

    /// In a preset, the apps on it; in a layout, its boxes by number.
    private var detail: String {
        guard model.draft.kind == .preset else {
            let numbers = boxes.map { String(model.number(of: $0)) }
            return (numbers.count == 1 ? "Box " : "Boxes ") + ListFormatter.localizedString(byJoining: numbers)
        }
        return boxes.map { box in
            switch box.binding {
            case .app(let bundleID): return model.appName(bundleID)
            case .mostRecent: return "Any recent window"
            case .empty: return "Box \(model.number(of: box))"
            }
        }.joined(separator: ", ")
    }

    private func icon(_ box: WindowBoxDraft.Box) -> NSImage? {
        guard case .app(let bundleID) = box.binding else { return nil }
        return model.appIcon(bundleID)
    }
}

/// Choosing what opens in a preset box: any recent window, an app that's open now, an installed app,
/// or one picked from disk. A search field narrows all three lists.
struct BoxAppPicker: View {
    @ObservedObject var model: BoxEditorModel
    let boxID: String
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private var running: [BoxEditorModel.AppChoice] { filtered(model.runningApps) }
    private var installed: [BoxEditorModel.AppChoice] { filtered(model.appsNotRunning) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if search.isEmpty {
                        row(icon: Image(systemName: "clock.arrow.circlepath"), title: "Any recent window",
                            detail: "Whatever you used last") { model.bind(.mostRecent, to: boxID) }
                    }
                    if !running.isEmpty { header("Open now") }
                    ForEach(running) { app in appRow(app) }
                    if !installed.isEmpty { header("Applications") }
                    ForEach(installed) { app in appRow(app) }
                    if running.isEmpty && installed.isEmpty && !search.isEmpty {
                        Text("No app called “\(search)”").foregroundStyle(.secondary).padding(12)
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            HStack {
                Button("Leave empty") { model.bind(.empty, to: boxID) }
                Spacer()
                Button("Other app…") { model.chooseOtherApp(for: boxID, above: NSApp.keyWindow) }
            }
            .controlSize(.small)
            .padding(10)
        }
        .frame(width: 300, height: 400)
        .onAppear { searchFocused = true }
    }

    private func filtered(_ apps: [BoxEditorModel.AppChoice]) -> [BoxEditorModel.AppChoice] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
    }

    private func appRow(_ app: BoxEditorModel.AppChoice) -> some View {
        let icon = model.appIcon(app.bundleID).map { Image(nsImage: $0) } ?? Image(systemName: "app")
        return row(icon: icon, title: app.name, detail: nil) { model.bind(.app(bundleID: app.bundleID), to: boxID) }
    }

    private func row(icon: Image, title: String, detail: String?, action: @escaping () -> Void) -> some View {
        BoxAppPickerRow(icon: icon, title: title, detail: detail, action: action)
    }
}

private struct BoxAppPickerRow: View {
    let icon: Image
    let title: String
    let detail: String?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon.resizable().scaledToFit().frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).lineLimit(1)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovered ? Color.accentColor.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovered = $0 }
    }
}
#endif
