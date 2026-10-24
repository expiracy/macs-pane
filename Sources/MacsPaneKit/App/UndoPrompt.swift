#if canImport(AppKit)
import AppKit
import SwiftUI

/// The prompt that drops from the top of the screen after a preset moves your windows: what happened
/// and an Undo button. It goes by itself after a few seconds (not while the pointer is on it), and
/// never takes focus from the windows it just arranged. The same Undo stays in the menu's Last change
/// box until it is used.
final class UndoPromptController {
    private var panel: NSPanel?
    private var dismiss: DispatchWorkItem?
    private var hovering = false

    static let lifetime: TimeInterval = 8
    private static let gap: CGFloat = 12

    func show(title: String, symbol: String, fact: String, on screen: NSScreen?, undo: @escaping () -> Void) {
        close()
        let view = UndoPromptView(title: title, symbol: symbol, fact: fact,
                                  undo: { [weak self] in
                                      self?.close()
                                      undo()
                                  },
                                  close: { [weak self] in self?.close() },
                                  hover: { [weak self] inside in self?.hover(inside) })
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - Self.gap - size.height))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        self.panel = panel
        scheduleDismiss()
    }

    func close() {
        dismiss?.cancel()
        dismiss = nil
        hovering = false
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.18; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }

    /// The pointer on the prompt holds it; leaving starts the countdown again.
    private func hover(_ inside: Bool) {
        hovering = inside
        if inside { dismiss?.cancel() } else { scheduleDismiss() }
    }

    private func scheduleDismiss() {
        dismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hovering else { return }
            self.close()
        }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime, execute: work)
    }
}

/// What applying did, and the one button that takes it back.
struct UndoPromptView: View {
    let title: String
    let symbol: String
    let fact: String
    let undo: () -> Void
    let close: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.13)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).lineLimit(1)
                Text(fact).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 16)
            Button("Undo", action: undo)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help("Put the windows back where they were")
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 10)
        .frame(minWidth: 320)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .fixedSize()
        .onHover(perform: hover)
        // The prompt never takes focus (the arranged windows keep it), so draw Undo as the front window would.
        .environment(\.controlActiveState, .key)
    }
}
#endif
