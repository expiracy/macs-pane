#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// The top of a Mac screen, wallpaper and a menu bar as tall as the camera housing, with a notch
/// drawing hanging from its top edge. Every setup lesson draws the notch here, at the shipped 1:1 size,
/// so the concave top corners meet a screen edge the way they do on the real display.
/// Every setup step is laid out the same way, top to bottom: one line saying what the picture is (with
/// the step's one button at its right), the picture at this one height, the steps to try, then a line
/// that follows what you just did. A step that reorders these reads as a different app.
enum SetupStage {
    static let height: CGFloat = 280
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
        .font(.system(size: 12))
        .foregroundStyle(Color.primary.opacity(0.72))
        .padding(.horizontal, 12)
        .frame(height: NotchGeometry.standardNotchSize.height)
        .accessibilityHidden(true)
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
