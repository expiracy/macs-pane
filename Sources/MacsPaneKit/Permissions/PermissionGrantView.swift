#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// Native companion for the open System Settings pane. The app's logo is the drag source; its
/// payload is the real app bundle.
struct PermissionGrantView: View {
    let grant: PermissionGrant
    let appName: String
    let appURL: URL
    @ObservedObject var model: PermissionGrantModel

    private var canDragApp: Bool { appURL.pathExtension == "app" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if grant.acceptsAppDrop && !model.granted { dragGuide }
            steps
            status
            if !model.granted { staleEntry }
            Divider()
            buttons
        }
        .padding(22)
        .frame(width: 420, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            MacsPaneLogo(size: 42).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.granted ? "\(grant.title) is on"
                                   : grant.acceptsAppDrop ? "Add \(appName) to \(grant.title)"
                                                          : "Allow \(grant.title) access")
                    .font(.headline)
                Text(model.granted ? grant.unlocksSentence : "\(appName) needs \(grant.title) for \(grant.unlocks).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The app on the left, a skeleton of the System Settings pane on the right, so the drag reads as
    /// "this icon goes into that list" — the pane is drawn to be recognised (title bar dots, sidebar,
    /// rows with switches), with the slot the app lands in outlined in the accent.
    private var dragGuide: some View {
        GroupBox {
            HStack(spacing: 12) {
                VStack(spacing: 7) {
                    if canDragApp {
                        MacsPaneLogo(size: 64)
                            .onDrag { NSItemProvider(contentsOf: appURL) ?? NSItemProvider() }
                            .onHover { inside in
                                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                            }
                            .help("Drag \(appName) into the \(grant.title) list in System Settings")
                            .accessibilityLabel("\(appName) application, drag into the \(grant.title) list")
                    } else {
                        MacsPaneLogo(size: 64).accessibilityHidden(true)
                    }
                    Text(canDragApp ? "Drag \(appName)" : appName).font(.caption.weight(.medium))
                }
                Image(systemName: "arrow.right")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                settingsSkeleton
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        } label: {
            Text(canDragApp ? "Drag the icon into the \(grant.title) list" : "Use the installed \(appName) app")
        }
    }

    /// A System Settings window in outline: enough of its shape to recognise, none of its words but
    /// the pane's name and the slot's.
    private var settingsSkeleton: some View {
        let bar = { (width: CGFloat) in Capsule().fill(Color.primary.opacity(0.14)).frame(width: width, height: 5) }
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.primary.opacity(0.2)).frame(width: 6, height: 6) }
                Spacer(minLength: 0)
                Text("System Settings").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7).frame(height: 18)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    bar(30); bar(22); bar(34); bar(26)
                    Spacer(minLength: 0)
                }
                .padding(7)
                .frame(width: 52, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text(grant.title).font(.system(size: 10, weight: .semibold))
                    skeletonRow { bar(46) }
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                        Text("Drop \(appName) here").font(.system(size: 9, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    Spacer(minLength: 0)
                }
                .padding(7)
            }
        }
        .frame(height: 104)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private func skeletonRow<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.14)).frame(width: 9, height: 9)
            label()
            Spacer(minLength: 0)
            Capsule().fill(Color.primary.opacity(0.2)).frame(width: 14, height: 8)
        }
        .padding(.horizontal, 6).frame(height: 18)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(grant.steps(appName: appName).enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 17)
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(index == 0 ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !grant.acceptsAppDrop {
                Text(grant.missingFromListHint(appName: appName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            if model.granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Permission granted").font(.subheadline.weight(.medium))
            } else {
                ProgressView().controlSize(.small)
                Text("Waiting for the permission").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var staleEntry: some View {
        Text(grant.staleEntryHint(appName: appName))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var buttons: some View {
        HStack(spacing: 9) {
            if !model.granted {
                Button("Start over") { model.startOver() }
                    .help("Replace a stale macOS permission entry for \(appName)")
            }
            Spacer(minLength: 0)
            Button("Close") { model.close() }
            if !model.granted {
                Button("Reopen System Settings") { model.openSettings() }
                    .help("Bring the \(grant.title) list in System Settings back to the front")
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
#endif
