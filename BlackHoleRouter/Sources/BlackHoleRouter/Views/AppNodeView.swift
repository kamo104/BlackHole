import SwiftUI
import AppKit

// MARK: - AppNodeView

/// A graph node representing a single running application's audio stream.
/// Apps that produce audio (isRunningOutput) show an **output port** on the right.
/// Apps that consume audio (isRunningInput)  show an **input port**  on the left.
/// This mirrors how PipeWire client nodes appear in qpwgraph.
struct AppNodeView: View {
    let app: AppStreamModel
    let isSelected: Bool
    let isPendingSource: Bool
    var onOutputPortTapped: () -> Void
    var onInputPortTapped: () -> Void
    var onNodeTapped: () -> Void

    var body: some View {
        ZStack {
            // ── Input port (left) ────────────────────────────────────────────────────
            if app.isRunningInput {
                PortIndicatorView(
                    side: .input,
                    color: RouterTheme.inputDeviceColor,
                    isHighlighted: isPendingSource,
                    onTap: onInputPortTapped)
                .offset(x: -RouterTheme.appNodeWidth / 2 - RouterTheme.portSize / 2)
            }

            // ── Output port (right) ──────────────────────────────────────────────────
            if app.isRunningOutput {
                PortIndicatorView(
                    side: .output,
                    color: app.isUsingBlackHoleSink
                        ? RouterTheme.blackHoleSinkColor
                        : RouterTheme.outputDeviceColor,
                    isHighlighted: isPendingSource,
                    onTap: onOutputPortTapped)
                .offset(x: RouterTheme.appNodeWidth / 2 + RouterTheme.portSize / 2)
            }

            // ── Node body ────────────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 7) {
                    appIconView
                    Text(app.appName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(headerColor.opacity(0.85))
                .cornerRadius(RouterTheme.nodeCornerRadius, corners: [.topLeft, .topRight])

                // Info rows
                VStack(alignment: .leading, spacing: 2) {
                    infoRow(label: "Type", value: roleLabel)
                    if !app.bundleID.isEmpty {
                        infoRow(label: "Bundle", value: shortBundleID)
                    }
                    if app.isUsingBlackHoleSink {
                        statusBadge("→ BlackHole Sink", color: RouterTheme.blackHoleSinkColor)
                    }
                    if app.isUsingBlackHoleSource {
                        statusBadge("← BlackHole Source", color: RouterTheme.blackHoleSourceColor)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(width: RouterTheme.appNodeWidth)
            .background(RouterTheme.nodeBG)
            .cornerRadius(RouterTheme.nodeCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: RouterTheme.nodeCornerRadius)
                    .stroke(isSelected ? RouterTheme.nodeSelected : RouterTheme.nodeBorder,
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .frame(width: RouterTheme.appNodeWidth)
        .contentShape(Rectangle())
        .onTapGesture { onNodeTapped() }
    }

    // MARK: - Sub-views

    private var appIconView: some View {
        Group {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .cornerRadius(4)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.45))
            Spacer()
            Text(value)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        }
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Helpers

    private var headerColor: Color {
        if app.isUsingBlackHoleSink   { return RouterTheme.blackHoleSinkColor }
        if app.isUsingBlackHoleSource { return RouterTheme.blackHoleSourceColor }
        if app.isRunningInput && app.isRunningOutput { return RouterTheme.ioDeviceColor }
        if app.isRunningOutput { return RouterTheme.outputDeviceColor }
        return RouterTheme.inputDeviceColor
    }

    private var roleLabel: String {
        if app.isRunningInput && app.isRunningOutput { return "Play + Record" }
        if app.isRunningOutput { return "Playback" }
        return "Recording"
    }

    private var shortBundleID: String {
        let parts = app.bundleID.components(separatedBy: ".")
        return parts.suffix(2).joined(separator: ".")
    }
}
