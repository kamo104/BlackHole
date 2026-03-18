import SwiftUI
import CoreAudio

// MARK: - NodeLayout

struct NodeLayout {
    static let nodeHeight: CGFloat = 140
    static let hSpacing: CGFloat = 260
    static let vSpacing: CGFloat = 160
    static let centerX: CGFloat = 600
    static let centerY: CGFloat = 340

    /// Lays out all nodes in a qpwgraph-style arrangement:
    /// playback apps (left) → BlackHole Sinks → BlackHole Sources → recording apps (right)
    /// Physical output devices are on the far left; input devices on the far right.
    static func autoLayout(devices: [AudioDeviceModel],
                           apps: [AppStreamModel]) -> [RoutingNodeID: CGPoint] {
        var positions: [RoutingNodeID: CGPoint] = [:]

        let sinks     = devices.filter { $0.isBlackHoleSink }
        let sources   = devices.filter { $0.isBlackHoleSource }
        let outOnly   = devices.filter { !$0.isBlackHole && $0.hasOutput && !$0.hasInput }
        let inOnly    = devices.filter { !$0.isBlackHole && $0.hasInput && !$0.hasOutput }
        let ioDevs    = devices.filter { !$0.isBlackHole && $0.hasInput && $0.hasOutput }

        let playbackApps  = apps.filter { $0.isRunningOutput }
        let recordingApps = apps.filter { $0.isRunningInput && !$0.isRunningOutput }

        // Physical output-only devices: far left
        for (i, d) in outOnly.enumerated() {
            positions[.device(d.id)] = CGPoint(x: centerX - hSpacing * 2.5,
                                                y: 120 + CGFloat(i) * vSpacing)
        }

        // Playback apps: left of BlackHole sinks
        for (i, a) in playbackApps.enumerated() {
            let y = centerY + CGFloat(i - playbackApps.count / 2) * vSpacing
            positions[.process(a.id)] = CGPoint(x: centerX - hSpacing * 1.3, y: y)
        }

        // BlackHole Sinks: centre-left column
        for (i, d) in sinks.enumerated() {
            let y = centerY + CGFloat(i - sinks.count / 2) * vSpacing
            positions[.device(d.id)] = CGPoint(x: centerX - hSpacing * 0.4, y: y)
        }

        // BlackHole Sources: centre-right column
        for (i, d) in sources.enumerated() {
            let y = centerY + CGFloat(i - sources.count / 2) * vSpacing
            positions[.device(d.id)] = CGPoint(x: centerX + hSpacing * 0.4, y: y)
        }

        // Recording apps: right of BlackHole sources
        for (i, a) in recordingApps.enumerated() {
            let y = centerY + CGFloat(i - recordingApps.count / 2) * vSpacing
            positions[.process(a.id)] = CGPoint(x: centerX + hSpacing * 1.3, y: y)
        }

        // Physical input-only devices: far right
        for (i, d) in inOnly.enumerated() {
            positions[.device(d.id)] = CGPoint(x: centerX + hSpacing * 2.5,
                                                y: 120 + CGFloat(i) * vSpacing)
        }

        // IO devices: bottom row
        for (i, d) in ioDevs.enumerated() {
            let y = centerY + vSpacing * 1.8
            positions[.device(d.id)] = CGPoint(
                x: centerX + CGFloat(i - ioDevs.count / 2) * hSpacing, y: y)
        }

        return positions
    }
}

// MARK: - GraphView

struct GraphView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var processManager: ProcessAudioManager
    @ObservedObject var routingGraph: RoutingGraph
    @ObservedObject var routingEngine: RoutingEngine

    @State private var draggingNodeID: RoutingNodeID?
    @State private var dragBasePosition: CGPoint = .zero
    @State private var canvasOffset: CGSize = .zero
    @State private var canvasDragStart: CGSize = .zero
    @State private var cursorPosition: CGPoint = .zero

    var body: some View {
        GeometryReader { _ in
            ZStack {
                RouterTheme.background.ignoresSafeArea()
                GridPattern().offset(canvasOffset)

                ZStack {
                    // Connection layer
                    Canvas { ctx, _ in
                        drawConnections(ctx: ctx)
                        drawPendingWire(ctx: ctx)
                    }
                    .allowsHitTesting(false)

                    // Device nodes
                    ForEach(audioManager.devices) { device in
                        deviceNodeWrapper(device)
                    }

                    // App stream nodes
                    ForEach(processManager.audioProcesses) { app in
                        appNodeWrapper(app)
                    }
                }
                .offset(canvasOffset)
                // Track cursor for the pending wire end point
                .onContinuousHover { phase in
                    if case .active(let loc) = phase {
                        cursorPosition = loc
                        if routingGraph.pendingSourceNodeID != nil {
                            // Offset by canvasOffset to get canvas-space coordinates
                            routingGraph.pendingWireEnd = CGPoint(
                                x: loc.x - canvasOffset.width,
                                y: loc.y - canvasOffset.height)
                        }
                    }
                }

                // Hint label while drawing a wire
                if routingGraph.pendingSourceNodeID != nil {
                    pendingWireLabel
                }

                // Error banner
                if let err = routingEngine.lastError {
                    errorBanner(message: err)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { v in
                        if draggingNodeID == nil {
                            canvasOffset = CGSize(
                                width: canvasDragStart.width + v.translation.width,
                                height: canvasDragStart.height + v.translation.height)
                        }
                    }
                    .onEnded { _ in canvasDragStart = canvasOffset }
            )
            .onTapGesture { routingGraph.cancelPendingConnection() }
            .onAppear { runAutoLayout() }
            .onChange(of: audioManager.devices)  { _ in handleDataChange() }
            .onChange(of: processManager.audioProcesses) { _ in handleDataChange() }
        }
    }

    // MARK: - Device Node Wrapper

    @ViewBuilder
    private func deviceNodeWrapper(_ device: AudioDeviceModel) -> some View {
        let nodeID      = RoutingNodeID.device(device.id)
        let pos         = routingGraph.getPosition(for: nodeID)
        let isSelected  = routingGraph.selectedNodeID == nodeID
        let isPending   = routingGraph.pendingSourceNodeID != nil
        let isDefaultOut = audioManager.defaultOutputDeviceID == device.id
        let isDefaultIn  = audioManager.defaultInputDeviceID  == device.id

        ZStack {
            // Input port
            if device.hasInput || device.isBlackHoleSink {
                PortIndicatorView(
                    side: .input,
                    color: RouterTheme.blackHoleSinkColor,
                    isHighlighted: isPending
                ) { handlePortTap(nodeID: nodeID, side: .input) }
                .offset(x: -RouterTheme.nodeWidth / 2 - RouterTheme.portSize / 2)
            }

            // Output port
            if device.hasOutput || device.isBlackHoleSource {
                PortIndicatorView(
                    side: .output,
                    color: RouterTheme.blackHoleSourceColor,
                    isHighlighted: routingGraph.pendingSourceNodeID == nodeID
                ) { handlePortTap(nodeID: nodeID, side: .output) }
                .offset(x: RouterTheme.nodeWidth / 2 + RouterTheme.portSize / 2)
            }

            DeviceNodeView(
                device: device,
                isSelected: isSelected,
                isDefaultOutput: isDefaultOut,
                isDefaultInput: isDefaultIn,
                onPortTapped: { side in handlePortTap(nodeID: nodeID, side: side) },
                onNodeTapped: { routingGraph.selectedNodeID = nodeID }
            )
            .gesture(nodeDrag(nodeID: nodeID, currentPos: pos))
        }
        .position(pos)
        .zIndex(draggingNodeID == nodeID ? 100 : isSelected ? 50 : 1)
    }

    // MARK: - App Node Wrapper

    @ViewBuilder
    private func appNodeWrapper(_ app: AppStreamModel) -> some View {
        let nodeID     = RoutingNodeID.process(app.id)
        let pos        = routingGraph.getPosition(for: nodeID)
        let isSelected = routingGraph.selectedNodeID == nodeID
        let isPendingSrc = routingGraph.pendingSourceNodeID == nodeID

        AppNodeView(
            app: app,
            isSelected: isSelected,
            isPendingSource: isPendingSrc,
            onOutputPortTapped: { handlePortTap(nodeID: nodeID, side: .output) },
            onInputPortTapped:  { handlePortTap(nodeID: nodeID, side: .input) },
            onNodeTapped:       { routingGraph.selectedNodeID = nodeID }
        )
        .gesture(nodeDrag(nodeID: nodeID, currentPos: pos))
        .position(pos)
        .zIndex(draggingNodeID == nodeID ? 100 : isSelected ? 50 : 1)
    }

    // MARK: - Drag Gesture

    private func nodeDrag(nodeID: RoutingNodeID, currentPos: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { v in
                if draggingNodeID != nodeID {
                    draggingNodeID = nodeID
                    dragBasePosition = currentPos
                }
                routingGraph.setPosition(
                    CGPoint(x: dragBasePosition.x + v.translation.width,
                            y: dragBasePosition.y + v.translation.height),
                    for: nodeID)
            }
            .onEnded { _ in draggingNodeID = nil }
    }

    // MARK: - Port Interaction

    private func handlePortTap(nodeID: RoutingNodeID, side: PortSide) {
        if let pendingID = routingGraph.pendingSourceNodeID {
            // Complete or cancel the pending wire
            if pendingID != nodeID {
                if let conn = routingGraph.completePendingConnection(to: nodeID) {
                    // Start a process tap if source is an app node
                    if case .process(_) = conn.source {
                        routingEngine.activateConnection(
                            source: conn.source,
                            destination: conn.destination,
                            connectionID: conn.id)
                        routingGraph.markConnectionActive(conn.id, active: true)
                    }
                } else {
                    routingGraph.cancelPendingConnection()
                }
            } else {
                routingGraph.cancelPendingConnection()
            }
        } else if side == .output {
            routingGraph.startPendingConnection(from: nodeID)
        }
    }

    // MARK: - Connection Drawing

    private func halfWidth(for nodeID: RoutingNodeID) -> CGFloat {
        switch nodeID {
        case .device:  return RouterTheme.nodeWidth    / 2
        case .process: return RouterTheme.appNodeWidth / 2
        }
    }

    private func drawConnections(ctx: GraphicsContext) {
        for conn in routingGraph.connections {
            let srcPos  = routingGraph.getPosition(for: conn.source)
            let dstPos  = routingGraph.getPosition(for: conn.destination)
            let srcHalf = halfWidth(for: conn.source)
            let dstHalf = halfWidth(for: conn.destination)

            let from = CGPoint(x: srcPos.x + srcHalf + RouterTheme.portSize / 2, y: srcPos.y)
            let to   = CGPoint(x: dstPos.x - dstHalf - RouterTheme.portSize / 2, y: dstPos.y)

            let isLive = routingEngine.activeConnectionIDs.contains(conn.id)

            let color: Color
            let lineWidth: CGFloat
            let dash: [CGFloat]
            if conn.isBlackHoleInternal {
                color = RouterTheme.blackHoleSourceColor.opacity(0.85)
                lineWidth = 2.5
                dash = []
            } else if conn.isInferred {
                color = .white.opacity(0.28)
                lineWidth = 1.5
                dash = [4, 4]
            } else if isLive {
                color = RouterTheme.nodeSelected.opacity(0.9)
                lineWidth = 2.0
                dash = []
            } else {
                color = RouterTheme.nodeSelected.opacity(0.55)
                lineWidth = 1.5
                dash = [5, 4]
            }

            let path = bezierPath(from: from, to: to)
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, dash: dash))
            drawArrow(ctx: ctx, from: from, to: to, color: color)
        }
    }

    private func drawPendingWire(ctx: GraphicsContext) {
        guard let srcID = routingGraph.pendingSourceNodeID,
              let end   = routingGraph.pendingWireEnd else { return }
        let srcPos  = routingGraph.getPosition(for: srcID)
        let srcHalf = halfWidth(for: srcID)
        let start   = CGPoint(x: srcPos.x + srcHalf + RouterTheme.portSize / 2, y: srcPos.y)
        let path = bezierPath(from: start, to: end)
        ctx.stroke(path, with: .color(.white.opacity(0.45)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
    }

    private func bezierPath(from: CGPoint, to: CGPoint) -> Path {
        var path = Path()
        let offset = max(abs(to.x - from.x) * 0.5, 60)
        path.move(to: from)
        path.addCurve(to: to,
                      control1: CGPoint(x: from.x + offset, y: from.y),
                      control2: CGPoint(x: to.x   - offset, y: to.y))
        return path
    }

    private func drawArrow(ctx: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        let midX  = (from.x + to.x) / 2
        let midY  = (from.y + to.y) / 2
        let angle = atan2(to.y - from.y, to.x - from.x)
        let size: CGFloat = 8
        var p = Path()
        p.move(to: CGPoint(x: midX - size * cos(angle - 0.4),
                           y: midY - size * sin(angle - 0.4)))
        p.addLine(to: CGPoint(x: midX, y: midY))
        p.addLine(to: CGPoint(x: midX - size * cos(angle + 0.4),
                              y: midY - size * sin(angle + 0.4)))
        ctx.stroke(p, with: .color(color), lineWidth: 1.5)
    }

    // MARK: - Auto Layout

    private func runAutoLayout() {
        let layout = NodeLayout.autoLayout(devices: audioManager.devices,
                                           apps: processManager.audioProcesses)
        for (id, pos) in layout { routingGraph.setPosition(pos, for: id) }
        refreshInferred()
    }

    private func handleDataChange() {
        // Position newly added nodes
        let layout = NodeLayout.autoLayout(devices: audioManager.devices,
                                           apps: processManager.audioProcesses)
        for (nodeID, pos) in layout {
            if routingGraph.getPosition(for: nodeID) == CGPoint(x: 400, y: 300) {
                routingGraph.setPosition(pos, for: nodeID)
            }
        }
        refreshInferred()
    }

    private func refreshInferred() {
        routingGraph.refreshInferredConnections(
            apps: processManager.audioProcesses,
            devices: audioManager.devices)
    }

    // MARK: - Status Overlays

    private var pendingWireLabel: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("Click a destination port to connect  •  Tap background to cancel")
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.72))
                    .foregroundColor(.white)
                    .cornerRadius(7)
                    .padding()
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                Spacer()
                Button("Dismiss") { routingEngine.lastError = nil }
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(red: 0.25, green: 0.18, blue: 0.08))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            Spacer()
        }
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
                    let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2,
                                     width: dotSize, height: dotSize)
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
