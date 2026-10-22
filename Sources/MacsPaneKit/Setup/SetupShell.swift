#if canImport(AppKit)
import SwiftUI

/// One step of a setup window, as the sidebar and heading show it.
struct SetupShellStep {
    let title: String
    let subtitle: String
    let symbol: String
}

/// The native setup window both apps use: the app's mark and name over a sidebar of steps, the step's
/// title and one line under it, the step itself, and a footer of Back · "n of m" · Continue (the last
/// step's button finishes).
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

    private var isLast: Bool { current == steps.count - 1 }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                heading
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                footer
            }
            .padding(.horizontal, 24)
        }
        .frame(minWidth: 1120, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                MacsPaneLogo(size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(appName).font(.headline)
                    Text("First-time setup").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 35)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let selected = current == index
                Button { current = index } label: {
                    HStack(spacing: 10) {
                        Image(systemName: step.symbol)
                            .frame(width: 18)
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                        Text(step.title)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.13))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .padding(.horizontal, 10)
            }
            Spacer()
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(18)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(steps[current].title)
                .font(.system(size: 27, weight: .semibold))
            Text(steps[current].subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 28)
        .padding(.bottom, 24)
    }

    private var footer: some View {
        HStack {
            if current > 0 {
                Button("Back") { current -= 1 }
            }
            Spacer()
            if let finishError, isLast {
                Label(finishError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.trailing, 10)
            }
            Text("\(current + 1) of \(steps.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.trailing, 10)
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
        .controlSize(.large)
        .padding(.vertical, 20)
    }
}
#endif
