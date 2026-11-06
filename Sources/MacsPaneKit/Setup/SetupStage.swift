#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// The top of a Mac screen, wallpaper and a menu bar as tall as the camera housing, with a notch
/// drawing hanging from its top edge, so the concave top corners meet a screen edge the way they do on
/// the real display.
/// Every setup step is laid out the same way, top to bottom: one line saying what the picture is (with
/// the step's one button at its right), the picture at this one height, the steps to try, then a line
/// that follows what you just did. A step that reorders these reads as a different app.
enum SetupStage {
    static let height: CGFloat = 280
    /// The picture is a real screen shrunk to fit: the notch, its menu bar and the open picker are
    /// drawn at this fraction of their size on a screen this much wider than the picture (about
    /// 1100 pt in the setup window). At 1:1 the picker would be squeezed onto a stage a third as wide
    /// as a Mac's, and its islands' titles cut short.
    static let scale: CGFloat = 0.64
    /// The menu bar, as tall as the camera housing, at the picture's scale.
    static var menuBarHeight: CGFloat { NotchGeometry.standardNotchSize.height * scale }
}

/// The line above a step's picture, with the step's buttons at its right. One height whether or not
/// there are buttons, so the picture starts at the same place on every step.
struct SetupIntroRow<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(text).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer()
            trailing()
        }
        .controlSize(.small)
        .frame(height: 24)
    }
}

extension SetupIntroRow where Trailing == EmptyView {
    init(text: String) { self.init(text: text) { EmptyView() } }
}

struct SetupDesktop<Notch: View>: View {
    var height: CGFloat?
    /// Off while a wide notch drawing covers the menu bar's ends, so no word is drawn half-hidden.
    var showsMenuItems = true
    @ViewBuilder var notch: () -> Notch
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: wallpaper, startPoint: .top, endPoint: .bottom)
            menuBar
            notch()
                .environment(\.colorScheme, .dark)
                .environment(\.notchScale, 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .frame(maxHeight: height == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        }
    }

    private var wallpaper: [Color] {
        scheme == .dark
            ? [Color(red: 0.19, green: 0.21, blue: 0.26), Color(red: 0.11, green: 0.12, blue: 0.15)]
            : [Color(red: 0.80, green: 0.85, blue: 0.91), Color(red: 0.70, green: 0.76, blue: 0.84)]
    }

    /// Only items that stay clear of an open 760 pt panel, so none is ever drawn half-covered.
    private var menuBar: some View {
        HStack(spacing: 10) {
            if showsMenuItems { Text("Finder").fontWeight(.semibold) }
            Spacer()
            if showsMenuItems {
                Image(systemName: "wifi")
                Text("9:41")
            }
        }
        .font(.system(size: 13 * SetupStage.scale))
        .foregroundStyle(Color.primary.opacity(0.72))
        .padding(.horizontal, 12 * SetupStage.scale)
        .frame(height: SetupStage.menuBarHeight)
        .accessibilityHidden(true)
    }
}

/// The notch at rest, hanging from the top middle of a `SetupDesktop`, as on a notched Mac.
struct SetupRestingNotch: View {
    private let m = NotchMetrics(scale: SetupStage.scale)

    var body: some View {
        NotchShape(topCornerRadius: m.rootTopRadiusCompact, bottomCornerRadius: m.rootBottomRadiusCompact)
            .fill(Color.black)
            .frame(width: NotchGeometry.standardNotchSize.width * SetupStage.scale, height: SetupStage.menuBarHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityHidden(true)
    }
}

/// Puts a sample desk's windows back where they started: a dark pill in the picture's bottom corner,
/// shown only once a window has moved, so it sits where you are looking and is gone when there is
/// nothing to undo.
struct SetupPutBackButton: View {
    @ObservedObject var lesson: WindowsLessonModel
    /// Hidden while a window is held, so it never sits under the drag.
    var hidden = false

    var body: some View {
        if lesson.windows != WindowsLessonModel.scattered && !hidden {
            Button { withAnimation(NotchMotion.settle) { lesson.scatter() } } label: {
                Label("Put the windows back", systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.62)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(10)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
        }
    }
}

/// Keys being pressed, each on a key cap, on a dark pill over a sample desk.
struct SetupKeyCaps: View {
    let shortcut: KeyShortcut

    private var caps: [String] {
        let symbols: [(KeyShortcut.Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { shortcut.modifiers.contains($0.0) }.map(\.1) + [shortcut.keyName]
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(minWidth: 30, minHeight: 30)
                    .padding(.horizontal, cap.count > 1 ? 6 : 0)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.16)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.22)))
            }
        }
        .padding(7)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .accessibilityLabel("Pressed \(shortcut.displayName)")
    }
}

struct SetupLessonStep: View {
    let title: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not yet")
    }
}
#endif
