#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// MacsPane Settings: what needs more room than a menu line — which layouts the drag-to-top picker
/// offers, and renaming or deleting presets and layouts. A native macOS window, kept to things
/// someone would really change: no timing or distance tuning.
struct MacsPaneSettingsView: View {
    @ObservedObject var model: MacsPaneModel
    @State private var pendingDelete: PendingDelete?
    @State private var importResult: String?

    private enum PendingDelete: Identifiable {
        case preset(SnapLayout), layout(WindowLayout)
        var id: String {
            switch self {
            case .preset(let preset): "preset-\(preset.id)"
            case .layout(let layout): "layout-\(layout.id)"
            }
        }
        var name: String {
            switch self {
            case .preset(let preset): preset.name
            case .layout(let layout): layout.name
            }
        }
    }

    var body: some View {
        Form {
            general
            dragBar
            presets
            if model.canImportFromNotchPlusPlus { notchPlusPlus }
            Section {
                LabeledContent("First-time setup") {
                    Button("Run setup again") { model.onShowSetup?() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)   // the form scrolls; the window stays a settings-window size
        .confirmationDialog(pendingDelete.map { "Delete “\($0.name)”?" } ?? "",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { target in
            Button("Delete", role: .destructive) {
                switch target {
                case .preset(let preset): model.deletePreset(preset.id)
                case .layout(let layout): model.deleteLayout(layout.id)
                }
            }
        } message: { target in
            switch target {
            case .preset: Text("The preset is removed. Your windows stay where they are.")
            case .layout: Text("The layout leaves the drag bar. Presets made from it keep their boxes.")
            }
        }
    }

    private var general: some View {
        Section {
            Toggle("Snap windows dragged to the top", isOn: Binding(
                get: { model.config.snap.enabled }, set: { model.setSnapping($0) }))
            Toggle("Open at login", isOn: Binding(
                get: { LoginItem.isEnabled }, set: { LoginItem.setEnabled($0); model.objectWillChange.send() }))
            if !model.isAuthorized {
                LabeledContent("Moving windows needs Accessibility") {
                    Button("Grant Access…") { model.requestAccess() }
                }
            }
        } footer: {
            Text("Drag a window by its title bar to the notch and rest there: the layouts open, "
                 + "and letting go on a box puts the window in it.")
        }
    }

    private var dragBar: some View {
        let ids = model.config.windows.dragBarLayoutIDs
        return Section {
            ForEach(model.config.windows.layoutCatalog) { layout in
                let offered = ids.contains(layout.id)
                let custom = model.config.windows.layouts.contains { $0.id == layout.id }
                HStack(spacing: 10) {
                    Toggle(isOn: Binding(get: { offered }, set: { _ in model.toggleBar(layout.id) })) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .help(offered ? "In the drag bar · click to take it out" : "Not in the drag bar · click to add it")
                    MacsPaneLayoutGlyph(boxes: layout.boxes)
                    if custom {
                        MacsPaneNameField(name: layout.name) { model.renameLayout(layout.id, to: $0) }
                        deleteButton { pendingDelete = .layout(layout) }
                    } else {
                        Text(layout.name)
                        Spacer()
                    }
                }
            }
        } header: {
            Text(ids.count == 1 ? "Drag bar · 1 layout" : "Drag bar · \(ids.count) layouts")
        } footer: {
            Text("The layouts the notch offers while you drag a window. “Save windows as a layout” in the menu adds yours.")
        }
    }

    private var presets: some View {
        Section("Presets") {
            if model.config.presets.isEmpty {
                Text("No presets yet. Arrange your windows, then choose “Save windows as a preset” in the menu.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.config.presets) { preset in
                HStack(spacing: 10) {
                    MacsPaneLayoutGlyph(boxes: preset.slots.filter { !$0.isRemoved }.map(\.region))
                    MacsPaneNameField(name: preset.name) { model.renamePreset(preset.id, to: $0) }
                    Button("Apply") { model.applyPreset(preset.id) }
                    deleteButton { pendingDelete = .preset(preset) }
                }
            }
        }
    }

    private var notchPlusPlus: some View {
        Section {
            LabeledContent {
                Button("Import") {
                    let added = model.importFromNotchPlusPlus()
                    importResult = added == 0 ? "Nothing new to import" : "\(added) imported"
                }
            } label: {
                Text("Layouts and presets from Notch++")
                if let importResult { Text(importResult) }
            }
        } footer: {
            Text("Adds the ones not here yet. Notch++'s own settings are never changed.")
        }
    }

    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "trash") }
            .buttonStyle(.borderless)
            .help("Delete")
            .accessibilityLabel("Delete")
    }
}

/// A name that saves when you press return or leave the field; an empty name takes the next default.
private struct MacsPaneNameField: View {
    let name: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { text = name }
            .onChange(of: name) { text = name }
            .onChange(of: focused) { if !focused, text != name { commit(text) } }
            .onSubmit { if text != name { commit(text) } }
    }
}

/// A layout's boxes as a small screen — the shape you'll get, so rows aren't told apart by name alone.
struct MacsPaneLayoutGlyph: View {
    let boxes: [SnapRegion]
    var size = CGSize(width: 32, height: 20)

    var body: some View {
        Canvas { context, size in
            let screen = CGRect(origin: .zero, size: size)
            context.stroke(Path(roundedRect: screen.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3),
                           with: .color(.secondary), lineWidth: 1)
            for box in boxes {
                let unit = box.unitRect
                // Unit rects are AppKit bottom-left; the canvas is top-left.
                let rect = CGRect(x: unit.minX * size.width, y: (1 - unit.maxY) * size.height,
                                  width: unit.width * size.width, height: unit.height * size.height)
                    .insetBy(dx: 1.5, dy: 1.5)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.accentColor.opacity(0.35)))
                context.stroke(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.accentColor), lineWidth: 0.75)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}
#endif
