#if canImport(AppKit)
import AppKit
import SwiftUI

/// One step of a setup window, as the sidebar and heading show it.
struct SetupShellStep {
    let title: String
    let subtitle: String
    let symbol: String
    /// The sidebar's label when the title is too long for it.
    var shortTitle: String?
}

/// The native setup window: the app's mark and name over a sidebar of numbered steps (ticked once
/// passed), the step's title and one line under it, the step itself, and a footer of Back · progress
/// dots · Continue (the last step's button finishes). The window's title bar is transparent, so the
/// sidebar runs to the top edge under the traffic lights.
struct SetupShell<Content: View>: View {
    let appName: String
    let steps: [SetupShellStep]
    @Binding var current: Int
    /// The last step's button ("Start using …").
    let finishTitle: String
    /// The sidebar's foot line.
    var footnote = "You can change these choices later in Settings."
    /// Why the last finish did not complete, beside the button on the last step.
    var finishError: String?
    let onFinish: () -> Void
    @ViewBuilder var content: () -> Content

    /// The window's content size: room for the drag lesson's stage beside the sidebar without the
    /// window crowding a 14" display.
    static var size: CGSize { CGSize(width: 1000, height: 660) }
    static var sidebarWidth: CGFloat { 224 }
    static var gutter: CGFloat { 36 }

    private var isLast: Bool { current == steps.count - 1 }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(SetupSidebarMaterial())
            Divider().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                heading
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .id(current)
                    .transition(.opacity)
                footer
            }
            .padding(.horizontal, Self.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.18), value: current)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                MacsPaneLogo(size: 40)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(appName).font(.system(size: 15, weight: .semibold))
                    Text("First-time setup").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    stepRow(index, step)
                }
            }
            .padding(.horizontal, 10)

            Spacer()
            Label {
                Text(footnote).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "menubar.arrow.up.rectangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
    }

    private func stepRow(_ index: Int, _ step: SetupShellStep) -> some View {
        let selected = current == index
        let passed = index < current
        return Button { current = index } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected || passed ? Color.accentColor : Color.primary.opacity(0.07))
                    if passed {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    } else {
                        Text("\(index + 1)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                }
                .foregroundStyle(selected || passed ? Color.white : Color.secondary)
                .frame(width: 22, height: 22)
                Text(step.shortTitle ?? step.title)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.75))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step \(index + 1), \(step.title)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Heading and footer

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(steps[current].title)
                .font(.system(size: 26, weight: .bold))
            Text(steps[current].subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 44)
        .padding(.bottom, 22)
    }

    private var footer: some View {
        ZStack {
            progressDots
            HStack(spacing: 12) {
                if current > 0 {
                    Button("Back") { current -= 1 }
                }
                Spacer()
                if let finishError, isLast {
                    Label(finishError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                if isLast {
                    Button(finishTitle, action: onFinish)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { current += 1 }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .controlSize(.large)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.accentColor : Color.primary.opacity(index < current ? 0.35 : 0.15))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(steps.count)")
    }
}

/// The system sidebar material, so the step list reads like every other Mac setup window.
private struct SetupSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A rounded, faintly filled panel: the one card style every setup step uses.
struct SetupCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// An SF Symbol on a tinted rounded square, the icon every setup card leads with.
struct SetupIconTile: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(tint.opacity(0.13)))
            .accessibilityHidden(true)
    }
}
#endif
