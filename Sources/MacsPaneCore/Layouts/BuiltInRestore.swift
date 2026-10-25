import Foundation

extension MacsPaneConfig {
    /// The built-in layouts you edited, where they differ from the original.
    private var editedBuiltIns: [WindowLayout] {
        WindowLayout.builtIns.compactMap { builtIn in
            windows.layouts.first { $0.id == builtIn.id && $0 != builtIn }
        }
    }

    /// Whether any built-in layout is deleted or edited, so restoring would bring something back.
    public var canRestoreBuiltInLayouts: Bool {
        !windows.deletedBuiltIns.isEmpty || !editedBuiltIns.isEmpty
    }

    /// Bring back every built-in layout as it first was, without losing anything of yours. A deleted
    /// one returns, out of the notch. One you edited stays as yours, under an id of its own, with its
    /// place, its spot in the notch and its shortcuts; the original returns right after it, out of the
    /// notch. An edit still named as the built-in is renamed "… (edited)" to tell the two apart.
    public mutating func restoreBuiltInLayouts() {
        let edits = editedBuiltIns
        var order = windows.layoutCatalog.map(\.id)
        for edit in edits {
            let newID = UUID().uuidString
            guard let index = windows.layouts.firstIndex(where: { $0.id == edit.id }) else { continue }
            windows.layouts[index].id = newID
            if edit.name == WindowLayout.builtIns.first(where: { $0.id == edit.id })?.name {
                windows.layouts[index].name = "\(edit.name) (edited)"
            }
            windows.dragBarLayoutIDs = windows.dragBarLayoutIDs.map { $0 == edit.id ? newID : $0 }
            if let place = order.firstIndex(of: edit.id) {
                order[place] = newID
                order.insert(edit.id, at: place + 1)
            }
            for (i, assigned) in shortcuts.enumerated() {
                if case let .layoutBox(layoutID, box) = assigned.action, layoutID == edit.id {
                    shortcuts[i].action = .layoutBox(layoutID: newID, box: box)
                }
            }
        }
        // The deleted ones come back where the order puts them: in their default place, or after those
        // you have ordered.
        if !edits.isEmpty { windows.layoutOrder = order }
        windows.restoreBuiltIns()
    }
}
