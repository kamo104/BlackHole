import SwiftUI
import CoreAudio

// MARK: - Design Constants

enum RouterTheme {
    static let background = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let nodeBG = Color(red: 0.18, green: 0.18, blue: 0.22)
    static let nodeBorder = Color(red: 0.30, green: 0.30, blue: 0.38)
    static let nodeSelected = Color(red: 0.42, green: 0.62, blue: 1.0)

    static let blackHoleSinkColor = Color(red: 0.96, green: 0.42, blue: 0.26)
    static let blackHoleSourceColor = Color(red: 0.36, green: 0.78, blue: 0.48)
    static let outputDeviceColor = Color(red: 0.42, green: 0.62, blue: 1.0)
    static let inputDeviceColor = Color(red: 0.88, green: 0.62, blue: 0.28)
    static let ioDeviceColor = Color(red: 0.72, green: 0.52, blue: 1.0)

    static let portSize: CGFloat = 12
    static let nodeWidth: CGFloat = 180
    static let appNodeWidth: CGFloat = 172
    static let nodeHeaderHeight: CGFloat = 36
    static let nodeRowHeight: CGFloat = 28
    static let nodeCornerRadius: CGFloat = 8
}

// MARK: - DeviceNodeView

struct DeviceNodeView: View {
    let device: AudioDeviceModel
    let isSelected: Bool
    let isDefaultOutput: Bool
    let isDefaultInput: Bool
    var onPortTapped: (PortSide) -> Void
    var onNodeTapped: () -> Void

    private var headerColor: Color {
        if device.isBlackHoleSink { return RouterTheme.blackHoleSinkColor }
        if device.isBlackHoleSource { return RouterTheme.blackHoleSourceColor }
        if device.hasInput && device.hasOutput { return RouterTheme.ioDeviceColor }
        if device.hasOutput { return RouterTheme.outputDeviceColor }
        return RouterTheme.inputDeviceColor
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Node background
            RoundedRectangle(cornerRadius: RouterTheme.nodeCornerRadius)
                .fill(RouterTheme.nodeBG)
                .overlay(
                    RoundedRectangle(cornerRadius: RouterTheme.nodeCornerRadius)
                        .stroke(
                            isSelected ? RouterTheme.nodeSelected : RouterTheme.nodeBorder,
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: deviceIcon)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.9))
                    Text(device.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(headerColor.opacity(0.85))
                .cornerRadius(RouterTheme.nodeCornerRadius,
                              corners: [.topLeft, .topRight])

                // Info rows
                VStack(alignment: .leading, spacing: 2) {
                    infoRow(label: "Type", value: device.typeLabel)

                    if device.sampleRate > 0 {
                        infoRow(label: "Sample Rate",
                                value: formatSampleRate(device.sampleRate))
                    }

                    if device.hasOutput && device.outputChannels > 0 {
                        infoRow(label: "Out Ch", value: "\(device.outputChannels)")
                    }
                    if device.hasInput && device.inputChannels > 0 {
                        infoRow(label: "In Ch", value: "\(device.inputChannels)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                // Status badges
                if isDefaultOutput || isDefaultInput {
                    HStack(spacing: 4) {
                        if isDefaultOutput {
                            badge(text: "System Out",
                                  color: RouterTheme.outputDeviceColor)
                        }
                        if isDefaultInput {
                            badge(text: "System In",
                                  color: RouterTheme.inputDeviceColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
        }
        .frame(width: RouterTheme.nodeWidth)
        .contentShape(Rectangle())
        .onTapGesture { onNodeTapped() }
    }

    // MARK: - Sub-views

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.25))
            .foregroundColor(color)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color.opacity(0.5), lineWidth: 1)
            )
    }

    // MARK: - Helpers

    private var deviceIcon: String {
        if device.isBlackHoleSink { return "arrow.down.circle.fill" }
        if device.isBlackHoleSource { return "arrow.up.circle.fill" }
        if device.hasInput && device.hasOutput { return "waveform" }
        if device.hasOutput { return "speaker.wave.2.fill" }
        return "mic.fill"
    }

    private func formatSampleRate(_ rate: Double) -> String {
        if rate >= 1000 {
            return String(format: "%.1f kHz", rate / 1000)
        }
        return String(format: "%.0f Hz", rate)
    }
}

// MARK: - Port Indicator View

struct PortIndicatorView: View {
    let side: PortSide
    let color: Color
    var isHighlighted: Bool = false
    var onTap: () -> Void

    var body: some View {
        Circle()
            .fill(isHighlighted ? color : color.opacity(0.6))
            .frame(width: RouterTheme.portSize, height: RouterTheme.portSize)
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 1.5)
            )
            .shadow(color: isHighlighted ? color.opacity(0.8) : .clear, radius: 4)
            .contentShape(Circle())
            .onTapGesture { onTap() }
    }
}

// MARK: - RoundedCorner helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let all: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
