#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// The Accessibility step's picture: System Settings open at Privacy & Security › Accessibility, with
/// MacsPane's switch ringed until it is on.
struct SetupAccessPicture: View {
    let granted: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var pulse = false

    private static let others = [("Terminal", "com.apple.Terminal", "terminal"),
                                 ("Script Editor", "com.apple.ScriptEditor2", "applescript")]

    var body: some View {
        SetupDesktop(height: SetupStage.height) {
            ZStack(alignment: .top) {
                SetupRestingNotch()
                window
                    .frame(width: 470)
                    .padding(.top, NotchGeometry.standardNotchSize.height + 22)
                    .environment(\.colorScheme, scheme)
            }
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(granted ? "System Settings, Accessibility, with MacsPane switched on."
                                    : "System Settings, Accessibility: switch MacsPane on in this list.")
    }

    private var window: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 10, height: 10) }
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 10)
                Text("Accessibility").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            Text("Allow the applications below to control your computer.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                row(Self.others[0].0, icon: appIcon(Self.others[0].1, symbol: Self.others[0].2), on: true)
                Divider()
                row("MacsPane", icon: AnyView(MacsPaneLogo(size: 20)), on: granted, ringed: !granted)
                Divider()
                row(Self.others[1].0, icon: appIcon(Self.others[1].1, symbol: Self.others[1].2), on: false)
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
    }

    private func row(_ name: String, icon: AnyView, on: Bool, ringed: Bool = false) -> some View {
        HStack(spacing: 10) {
            icon.frame(width: 20, height: 20)
            Text(name).font(.callout.weight(name == "MacsPane" ? .semibold : .regular))
            Spacer()
            ZStack {
                if ringed {
                    Capsule()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: 40, height: 24)
                        .scaleEffect(pulse ? 1.45 : 1)
                        .opacity(pulse ? 0 : 0.9)
                }
                SetupDrawnSwitch(on: on)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private func appIcon(_ bundleID: String, symbol: String) -> AnyView {
        if let icon = SnapAppIcons.icon(bundleID: bundleID) {
            return AnyView(Image(nsImage: icon).resizable())
        }
        return AnyView(Image(systemName: symbol).foregroundStyle(.secondary))
    }
}

/// A switch drawn, not clicked: the pictures show settings without being settings.
struct SetupDrawnSwitch: View {
    let on: Bool

    var body: some View {
        Capsule()
            .fill(on ? Color.accentColor : Color.primary.opacity(0.15))
            .frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                    .padding(2)
            }
            .animation(.easeOut(duration: 0.2), value: on)
    }
}

/// The layouts step's picture: the notch drawn open over the sample desk, offering exactly the layouts
/// ticked under it, in order; it changes as you tick.
struct SetupLayoutsPreview: View {
    @StateObject private var driver: SetupNotchDriver
    let config: MacsPaneConfig

    init(config: MacsPaneConfig) {
        self.config = config
        _driver = StateObject(wrappedValue: SetupNotchDriver(config: config))
    }

    var body: some View {
        SetupDesktop(height: SetupStage.height, showsMenuItems: false) {
            GeometryReader { geo in SetupNotchStage(driver: driver, size: geo.size, interactive: false) }
        }
        .allowsHitTesting(false)
        .onAppear { driver.showPickerOpen() }
        .onChange(of: config.windows) { _, _ in
            withAnimation(NotchMotion.fast) { driver.host.apply(WindowsLessonModel.config(from: config)) }
            driver.host.dwellMs = 0
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The notch open, offering the layouts you've ticked.")
    }
}
#endif
