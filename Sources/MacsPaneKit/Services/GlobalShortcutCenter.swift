#if canImport(AppKit)
import AppKit
import Carbon.HIToolbox
import MacsPaneCore

/// Listens for the keys in `MacsPaneConfig.shortcuts` in every app, through Carbon's system hot keys:
/// they need no permission, and the key is taken, so the app you are in never also sees it. Main
/// thread only.
final class GlobalShortcutCenter {
    /// A registered shortcut was pressed.
    var onPress: ((ShortcutAction) -> Void)?
    /// Off while the editor records a shortcut, so pressing one already in use records it instead of
    /// running it.
    var isSuspended = false {
        didSet { if isSuspended != oldValue { reregister() } }
    }

    private var assigned: [AssignedShortcut] = []
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: ShortcutAction] = [:]
    private var handler: EventHandlerRef?
    /// 'MPan', which tells MacsPane's hot keys from any other's.
    private static let signature: OSType = 0x4D50_616E

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Listen for exactly these shortcuts from now on.
    func register(_ shortcuts: [AssignedShortcut]) {
        guard shortcuts != assigned else { return }
        assigned = shortcuts
        reregister()
    }

    private func reregister() {
        unregisterAll()
        guard !isSuspended, !assigned.isEmpty else { return }
        installHandlerIfNeeded()
        for (index, shortcut) in assigned.enumerated() {
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.shortcut.keyCode),
                                             Self.carbonModifiers(shortcut.shortcut.modifiers),
                                             id, GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                NSLog("MacsPane: shortcut \(shortcut.shortcut.displayName) is taken (\(status))")
                continue
            }
            refs.append(ref)
            actions[id.id] = shortcut.action
        }
    }

    private func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, refcon in
            guard let event, let refcon else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == GlobalShortcutCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let center = Unmanaged<GlobalShortcutCenter>.fromOpaque(refcon).takeUnretainedValue()
            center.pressed(id.id)
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func pressed(_ id: UInt32) {
        guard let action = actions[id] else { return }
        onPress?(action)
    }

    static func carbonModifiers(_ modifiers: KeyShortcut.Modifiers) -> UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}

extension KeyShortcut {
    /// The shortcut a key press makes: its key, the modifiers held, and what it types on this layout
    /// with none held ("1", not the "!" ⇧ makes of it).
    init(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self.init(keyCode: event.keyCode, modifiers: modifiers, character: event.characters(byApplyingModifiers: []))
    }
}
#endif
