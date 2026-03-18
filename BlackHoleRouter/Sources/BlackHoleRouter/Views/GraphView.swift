import SwiftUI
import CoreAudio

// MARK: - LayoutHelper

struct NodeLayout {
    static let nodeHeight: CGFloat = 140
    static let hSpacing: CGFloat = 260
    static let vSpacing: CGFloat = 160
    static let centerX: CGFloat = 500
    static let centerY: CGFloat = 300

    /// Automatically positions devices in a pipewire-style layout:
    /// Input devices on the left, BlackHole center, output devices on the right.
    static func autoLayout(devices: [AudioDeviceModel]) -> [AudioObjectID: CGPoint] {
        var positions: [AudioObjectID: CGPoint] = [:]

        let sinks = devices.filter { $0.isBlackHoleSink }
        let sources = devices.filter { $0.isBlackHoleSource }
        let outputOnly = devices.filter { !$0.isBlackHole && $0.hasOutput && !$0.hasInput }
        let inputOnly = devices.filter { !$0.isBlackHole && $0.hasInput && !$0.hasOutput }
        let ioDevices = devices.filter { !$0.isBlackHole && $0.hasInput && $0.hasOutput }

        // BlackHole Sink(s): center-left column
        for (i, d) in sinks.enumerated() {
            let y = centerY + CGFloat(i - sinks.count / 2) * vSpacing
            positions[d.id] = CGPoint(x: centerX - hSpacing, y: y)
        }

        // BlackHole Source(s): center-right column
        for (i, d) in sources.enumerated() {
            let y = centerY + CGFloat(i - sources.count / 2) * vSpacing
            positions[d.id] = CGPoint(x: centerX + hSpacing, y: y)
        }

        // Output-only devices: far left column
        for (i, d) in outputOnly.enumerated() {
            let y = 120 + CGFloat(i) * vSpacing
            positions[d.id] = CGPoint(x: centerX - hSpacing * 2.2, y: y)
        }

        // Input-only devices: far right column
        for (i, d) in inputOnly.enumerated() {
            let y = 120 + CGFloat(i) * vSpacing
            positions[d.id] = CGPoint(x: centerX + hSpacing * 2.2, y: y)
        }

        // IO devices: bottom
        for (i, d) in ioDevices.enumerated() {
            let y = centerY + vSpacing * 1.8
            positions[d.id] = CGPoint(x: centerX + CGFloat(i - ioDevices.count / 2) * hSpacing, y: y)
        }

        return positions
    }
}

// MARK: - ConnectionPath

struct ConnectionPath: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let controlOffset = abs(to.x - from.x) * 0.5
        path.move(to: from)
        path.addCurve(
            to: to,
            control1: CGPoint(x: from.x + controlOffset, y: from.y),
            control2: CGPoint(x: to.x - controlOffset, y: to.y)
        )
        return path
    }
}

// MARK: - GraphView

struct GraphView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var graphState: GraphState

    @State private var draggingDeviceID: AudioObjectID?
    @State private var canvasOffset: CGSize = .zero
    @State private var canvasDragStart: CGSize = .zero
    @State private var pendingLineEnd: CGPoint? = nil
    @State private var pendingLineStart: CGPoint? = nil
    @State private var scale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                RouterTheme.background
                    .ignoresSafeArea()

                // Grid
                GridPattern()
                    .offset(canvasOffset)

                // Canvas with nodes and connections
                ZStack {
                    // Draw connections
                    Canvas { ctx, size in
                        drawConnections(ctx: ctx, size: size)
                        drawPendingLine(ctx: ctx, size: size)
                    }
                    .allowsHitTesting(false)

                    // Nodes
                    ForEach(audioManager.devices) { device in
                        nodeView(for: device)
                    }
                }
                .offset(canvasOffset)
                .scaleEffect(scale, anchor: .center)

                // Pending connection overlay
                if pendingLineEnd != nil {
                    pendingConnectionLabel
                }
            }
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if draggingDeviceID == nil {
                            canvasOffset = CGSize(
                                width: canvasDragStart.width + value.translation.width,
                                height: canvasDragStart.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        canvasDragStart = canvasOffset
                    }
            )
            .onAppear {
                let layout = NodeLayout.autoLayout(devices: audioManager.devices)
                for (id, pos) in layout {
                    graphState.setPosition(pos, for: id)
                }
                updateSystemDefaultConnections()
            }
            .onChange(of: audioManager.devices) { newDevices in
                // Only auto-layout new devices not yet positioned
                for device in newDevices where graphState.getPosition(for: device.id) == .zero {
                    let layout = NodeLayout.autoLayout(devices: newDevices)
                    if let pos = layout[device.id] {
                        graphState.setPosition(pos, for: device.id)
                    }
                }
                updateSystemDefaultConnections()
            }
            .onChange(of: audioManager.defaultOutputDeviceID) { _ in
                updateSystemDefaultConnections()
            }
            .onChange(of: audioManager.defaultInputDeviceID) { _ in
                updateSystemDefaultConnections()
            }
        }
    }

    // MARK: - Node View Builder

    @ViewBuilder
    private func nodeView(for device: AudioDeviceModel) -> some View {
        let pos = graphState.getPosition(for: device.id)
        let isSelected = graphState.selectedDeviceID == device.id
        let isDefaultOut = audioManager.defaultOutputDeviceID == device.id
        let isDefaultIn = audioManager.defaultInputDeviceID == device.id

        ZStack {
            // Input port (left side) - audio enters the device
            if device.hasInput || device.isBlackHoleSink {
                PortIndicatorView(
                    side: .input,
                    color: RouterTheme.blackHoleSinkColor,
                    isHighlighted: graphState.pendingConnectionSide == .output
                ) {
                    completePendingConnection(toDevice: device, portSide: .input)
                }
                .offset(x: -RouterTheme.nodeWidth / 2 - RouterTheme.portSize / 2, y: 0)
            }

            // Output port (right side) - audio leaves the device
            if device.hasOutput || device.isBlackHoleSource {
                PortIndicatorView(
                    side: .output,
                    color: RouterTheme.blackHoleSourceColor,
                    isHighlighted: false
                ) {
                    startPendingConnection(fromDevice: device, portSide: .output, position: pos)
                }
                .offset(x: RouterTheme.nodeWidth / 2 + RouterTheme.portSize / 2, y: 0)
            }

            // Device node
            DeviceNodeView(
                device: device,
                isSelected: isSelected,
                isDefaultOutput: isDefaultOut,
                isDefaultInput: isDefaultIn,
                onPortTapped: { side in
                    handlePortTap(device: device, side: side)
                },
                onNodeTapped: {
                    graphState.selectedDeviceID = device.id
                }
            )
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        draggingDeviceID = device.id
                        let base = pos
                        graphState.setPosition(
                            CGPoint(x: base.x + value.translation.width,
                                    y: base.y + value.translation.height),
                            for: device.id
                        )
                    }
                    .onEnded { _ in
                        draggingDeviceID = nil
                    }
            )
        }
        .position(pos)
        .animation(.interactiveSpring(), value: pos)
        .zIndex(draggingDeviceID == device.id ? 100 : isSelected ? 50 : 1)
    }

    // MARK: - Connection Drawing

    private func drawConnections(ctx: GraphicsContext, size: CGSize) {
        for conn in graphState.connections {
            guard
                let src = audioManager.devices.first(where: { $0.id == conn.sourceDeviceID }),
                let dst = audioManager.devices.first(where: { $0.id == conn.destinationDeviceID })
            else { continue }

            let srcPos = graphState.getPosition(for: src.id)
            let dstPos = graphState.getPosition(for: dst.id)

            // Output port is on right side of source node
            let fromPt = CGPoint(
                x: srcPos.x + RouterTheme.nodeWidth / 2 + RouterTheme.portSize / 2,
                y: srcPos.y
            )
            // Input port is on left side of destination node
            let toPt = CGPoint(
                x: dstPos.x - RouterTheme.nodeWidth / 2 - RouterTheme.portSize / 2,
                y: dstPos.y
            )

            let color: Color = conn.isSystemDefault
                ? RouterTheme.blackHoleSourceColor.opacity(0.9)
                : RouterTheme.nodeSelected.opacity(0.7)

            let path = bezierPath(from: fromPt, to: toPt)
            ctx.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: conn.isSystemDefault ? 2.5 : 1.5,
                                   dash: conn.isSystemDefault ? [] : [5, 4])
            )

            // Direction arrow at midpoint
            drawArrow(ctx: ctx, from: fromPt, to: toPt, color: color)
        }
    }

    private func drawPendingLine(ctx: GraphicsContext, size: CGSize) {
        guard let start = pendingLineStart, let end = pendingLineEnd else { return }
        let path = bezierPath(from: start, to: end)
        ctx.stroke(
            path,
            with: .color(.white.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
        )
    }

    private func bezierPath(from: CGPoint, to: CGPoint) -> Path {
        var path = Path()
        let offset = max(abs(to.x - from.x) * 0.5, 60)
        path.move(to: from)
        path.addCurve(
            to: to,
            control1: CGPoint(x: from.x + offset, y: from.y),
            control2: CGPoint(x: to.x - offset, y: to.y)
        )
        return path
    }

    private func drawArrow(ctx: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2
        let angle = atan2(to.y - from.y, to.x - from.x)
        let arrowSize: CGFloat = 8

        var arrowPath = Path()
        arrowPath.move(to: CGPoint(
            x: midX - arrowSize * cos(angle - 0.4),
            y: midY - arrowSize * sin(angle - 0.4)
        ))
        arrowPath.addLine(to: CGPoint(x: midX, y: midY))
        arrowPath.addLine(to: CGPoint(
            x: midX - arrowSize * cos(angle + 0.4),
            y: midY - arrowSize * sin(angle + 0.4)
        ))
        ctx.stroke(arrowPath, with: .color(color), lineWidth: 1.5)
    }

    // MARK: - Connection Interaction

    private func startPendingConnection(fromDevice device: AudioDeviceModel,
                                        portSide: PortSide,
                                        position: CGPoint) {
        graphState.pendingConnectionSourceID = device.id
        graphState.pendingConnectionSide = portSide
        pendingLineStart = CGPoint(
            x: position.x + RouterTheme.nodeWidth / 2,
            y: position.y
        )
    }

    private func completePendingConnection(toDevice destination: AudioDeviceModel,
                                           portSide: PortSide) {
        guard
            let sourceID = graphState.pendingConnectionSourceID,
            sourceID != destination.id
        else {
            clearPendingConnection()
            return
        }

        graphState.addConnection(from: sourceID, to: destination.id)
        clearPendingConnection()
    }

    private func clearPendingConnection() {
        graphState.pendingConnectionSourceID = nil
        graphState.pendingConnectionSide = nil
        pendingLineStart = nil
        pendingLineEnd = nil
    }

    private func handlePortTap(device: AudioDeviceModel, side: PortSide) {
        if graphState.pendingConnectionSourceID != nil {
            completePendingConnection(toDevice: device, portSide: side)
        } else {
            startPendingConnection(fromDevice: device, portSide: side,
                                   position: graphState.getPosition(for: device.id))
        }
    }

    // MARK: - System Default Connections

    private func updateSystemDefaultConnections() {
        graphState.removeAllSystemDefaultConnections()

        // Show BlackHole internal routing: Sink → Source (the ring buffer)
        let sinkDevices = audioManager.devices.filter { $0.isBlackHoleSink }
        let sourceDevices = audioManager.devices.filter { $0.isBlackHoleSource }
        for sink in sinkDevices {
            for source in sourceDevices {
                graphState.addConnection(
                    from: sink.id,
                    to: source.id,
                    isSystemDefault: true
                )
            }
        }
    }

    // MARK: - Pending Line Overlay

    private var pendingConnectionLabel: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("Click a destination port to connect, or press Escape to cancel")
                    .font(.system(size: 12))
                    .padding(8)
                    .background(.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .padding()
            }
        }
        .onTapGesture { clearPendingConnection() }
    }
}

// MARK: - Grid Pattern

struct GridPattern: View {
    let spacing: CGFloat = 30
    let dotSize: CGFloat = 1.5

    var body: some View {
        Canvas { ctx, size in
            let color = Color(red: 0.25, green: 0.25, blue: 0.30).opacity(0.5)
            var x: CGFloat = 0
            while x < size.width + spacing {
                var y: CGFloat = 0
                while y < size.height + spacing {
                    let rect = CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    ctx.fill(Path(ellipseIn: rect), with: .color(color))
                    y += spacing
                }
                x += spacing
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
