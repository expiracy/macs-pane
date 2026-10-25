#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// A shortcut's chip in the editor: "Add shortcut", the keys it has ("⌃⌥1") with a clear button, or,
/// once clicked, a prompt waiting for the keys. On a box it is drawn white on the box's glass; in
/// the toolbar, as the toolbar's own controls are.
struct ShortcutRecorder: View {
    @ObservedObject var model: BoxEditorModel
    let target: BoxEditorModel.ShortcutTarget
    var onGlass = false
    var compact = false

    private var recording: Bool { model.recordingShortcut == target }
    private var shortcut: KeyShortcut? { model.shortcut(for: target) }

    var body: some View {
        HStack(spacing: 4) {
            Button { model.recordShortcut(for: target) } label: { label }
                .buttonStyle(.plain)
                .help(help)
            if let shortcut, !recording {
                Button { model.setShortcut(nil, for: target) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(onGlass ? Color.white : .secondary, onGlass ? Color.black.opacity(0.4) : .clear)
                }
                .buttonStyle(.plain)
                .help("Remove \(shortcut.displayName)")
                .accessibilityLabel("Remove shortcut")
            }
        }
        .font(.system(size: compact ? 11 : 12, weight: .semibold))
        .fixedSize()
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: "keyboard")
            if recording {
                Text(model.shortcutHint ?? "Type a shortcut")
            } else if let shortcut {
                Text(shortcut.displayName).monospacedDigit()
            } else if !compact {
                Text("Add shortcut")
            }
        }
        .foregroundStyle(onGlass ? Color.white : recording ? Color.accentColor : .primary)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background {
            Capsule().fill(onGlass ? Color.black.opacity(recording ? 0.65 : 0.45)
                                   : Color.primary.opacity(recording ? 0.04 : 0.07))
        }
        .overlay {
            if recording {
                Capsule().strokeBorder(onGlass ? Color.white : Color.accentColor,
                                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .contentShape(Capsule())
    }

    private var help: String {
        if recording { return "Press the keys for this shortcut; esc keeps the one it had, ⌫ removes it" }
        if let from = model.shortcutTakenFrom(target) { return "Saving moves this shortcut here from \(from)" }
        switch target {
        case .box: return "A shortcut that sends the window you're in to this box"
        case .preset: return "A shortcut that applies this preset from any app"
        }
    }
}
#endif
