import SwiftUI
import CoreAudio

struct SidebarView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var processManager: ProcessAudioManager
    @ObservedObject var routingGraph: RoutingGraph
    @ObservedObject var routingEngine: RoutingEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundColor(RouterTheme.blackHoleSourceColor)
                Text("BlackHole Router")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RouterTheme.nodeBG)

            Divider().background(RouterTheme.nodeBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── App Streams ──────────────────────────────────────────────────
                    let playbackApps  = processManager.audioProcesses.filter { $0.isRunningOutput }
                    let recordingApps = processManager.audioProcesses.filter { $0.isRunningInput && !$0.isRunningOutput }

                    if !playbackApps.isEmpty {
                        sectionHeader("Playback Apps",
                                      icon: "play.circle.fill",
                                      color: RouterTheme.outputDeviceColor)
                        ForEach(playbackApps) { app in
                            appRow(app)
                        }
                    }

                    if !recordingApps.isEmpty {
                        sectionHeader("Recording Apps",
                                      icon: "mic.circle.fill",
                                      color: RouterTheme.inputDeviceColor)
                        ForEach(recordingApps) { app in
                            appRow(app)
                        }
                    }

                    if processManager.audioProcesses.isEmpty {
                        if #available(macOS 14.0, *) {
                            sectionHeader("App Streams",
                                          icon: "app.fill",
                                          color: RouterTheme.outputDeviceColor)
                            Text("No apps are currently playing or recording audio.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 14)
                                .padding(.top, 4)
                        } else {
                            sectionHeader("App Streams",
                                          icon: "app.fill",
                                          color: RouterTheme.outputDeviceColor)
                            Text("Per-app streams require macOS 14 or later.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 14)
                                .padding(.top, 4)
                        }
                    }

                    // ── BlackHole Devices ────────────────────────────────────────────
                    let blackHoleDevices = audioManager.devices.filter { $0.isBlackHole }
                    if !blackHoleDevices.isEmpty {
                        sectionHeader("BlackHole Devices",
                                      icon: "infinity.circle.fill",
                                      color: RouterTheme.blackHoleSinkColor)
                        ForEach(blackHoleDevices) { device in
                            deviceRow(device)
                        }
                    }

                    // ── System Defaults ──────────────────────────────────────────────
                    sectionHeader("System Defaults",
                                  icon: "gearshape.fill",
                                  color: RouterTheme.ioDeviceColor)
                    systemDefaultsSection

                    // ── All Devices ──────────────────────────────────────────────────
                    let regularDevices = audioManager.devices.filter { !$0.isBlackHole }
                    if !regularDevices.isEmpty {
                        sectionHeader("All Audio Devices",
                                      icon: "waveform",
                                      color: RouterTheme.outputDeviceColor)
                        ForEach(regularDevices) { device in
                            deviceRow(device)
                        }
                    }

                    // ── Active Routing ───────────────────────────────────────────────
                    let userConns = routingGraph.connections.filter {
                        !$0.isBlackHoleInternal && !$0.isInferred
                    }
                    if !userConns.isEmpty {
                        sectionHeader("Active Routing",
                                      icon: "arrow.triangle.branch",
                                      color: RouterTheme.nodeSelected)
                        ForEach(userConns) { conn in
                            connectionRow(conn)
                        }
                    }

                    // ── Inferred (read-only) ─────────────────────────────────────────
                    let inferred = routingGraph.connections.filter { $0.isInferred }
                    if !inferred.isEmpty {
                        sectionHeader("Current App→Device",
                                      icon: "arrow.right.circle",
                                      color: .white.opacity(0.35))
                        ForEach(inferred) { conn in
                            inferredConnectionRow(conn)
                        }
                    }
                }
                .padding(.bottom, 16)
            }

            Divider().background(RouterTheme.nodeBorder)

            // Bottom bar
            HStack {
                Button(action: {
                    audioManager.refresh()
                    processManager.refresh()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(RouterTheme.outputDeviceColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(audioManager.devices.count) devices")
                    Text("\(processManager.audioProcesses.count) apps")
                }
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .padding(.trailing, 14)
            }
            .background(RouterTheme.nodeBG)
        }
        .background(Color(red: 0.13, green: 0.13, blue: 0.16))
    }

    // MARK: - App Row

    private func appRow(_ app: AppStreamModel) -> some View {
        let nodeID = RoutingNodeID.process(app.id)
        let isSelected = routingGraph.selectedNodeID == nodeID

        return Button(action: {
            routingGraph.selectedNodeID = isSelected ? nil : nodeID
        }) {
            HStack(spacing: 8) {
                // App icon or colour dot
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .cornerRadius(3)
                } else {
                    Circle()
                        .fill(app.isUsingBlackHoleSink
                              ? RouterTheme.blackHoleSinkColor
                              : RouterTheme.outputDeviceColor)
                        .frame(width: 7, height: 7)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.appName)
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.85))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if app.isUsingBlackHoleSink {
                            Text("→ BlackHole")
                                .font(.system(size: 9))
                                .foregroundColor(RouterTheme.blackHoleSinkColor)
                        }
                        if app.isUsingBlackHoleSource {
                            Text("← BlackHole")
                                .font(.system(size: 9))
                                .foregroundColor(RouterTheme.blackHoleSourceColor)
                        }
                        if !app.isUsingBlackHoleSink && !app.isUsingBlackHoleSource {
                            Text("PID \(app.pid)")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }

                Spacer()

                // Live routing indicator
                let appConns = routingGraph.connections.filter {
                    $0.source == nodeID && routingEngine.activeConnectionIDs.contains($0.id)
                }
                if !appConns.isEmpty {
                    Image(systemName: "dot.radiowaves.right")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(isSelected ? RouterTheme.nodeBorder.opacity(0.5) : .clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Focus in Graph") { routingGraph.selectedNodeID = nodeID }
            Divider()
            Button("Start Wire from this App") {
                routingGraph.startPendingConnection(from: nodeID)
            }
        }
    }

    // MARK: - Device Row

    private func deviceRow(_ device: AudioDeviceModel) -> some View {
        let nodeID = RoutingNodeID.device(device.id)
        let isSelected   = routingGraph.selectedNodeID == nodeID
        let isDefaultOut = audioManager.defaultOutputDeviceID == device.id
        let isDefaultIn  = audioManager.defaultInputDeviceID  == device.id

        return Button(action: {
            routingGraph.selectedNodeID = isSelected ? nil : nodeID
        }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(device.isBlackHoleSink
                          ? RouterTheme.blackHoleSinkColor
                          : device.isBlackHoleSource
                          ? RouterTheme.blackHoleSourceColor
                          : device.hasInput && device.hasOutput
                          ? RouterTheme.ioDeviceColor
                          : device.hasOutput
                          ? RouterTheme.outputDeviceColor
                          : RouterTheme.inputDeviceColor)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.85))
                        .lineLimit(1)
                    Text(device.typeLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if isDefaultOut {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 9))
                            .foregroundColor(RouterTheme.outputDeviceColor)
                    }
                    if isDefaultIn {
                        Image(systemName: "mic")
                            .font(.system(size: 9))
                            .foregroundColor(RouterTheme.inputDeviceColor)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(isSelected ? RouterTheme.nodeBorder.opacity(0.5) : .clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if device.hasOutput {
                Button("Set as Default Output") {
                    audioManager.setDefaultOutputDevice(device.id)
                }
            }
            if device.hasInput {
                Button("Set as Default Input") {
                    audioManager.setDefaultInputDevice(device.id)
                }
            }
        }
    }

    // MARK: - System Defaults

    private var systemDefaultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            defaultRow(icon: "speaker.wave.2",
                       iconColor: RouterTheme.outputDeviceColor,
                       label: "Output",
                       deviceID: audioManager.defaultOutputDeviceID)
            defaultRow(icon: "mic",
                       iconColor: RouterTheme.inputDeviceColor,
                       label: "Input",
                       deviceID: audioManager.defaultInputDeviceID)

            // Quick routing shortcuts
            if let sinkID = audioManager.devices.first(where: { $0.isBlackHoleSink })?.id,
               let sourceID = audioManager.devices.first(where: { $0.isBlackHoleSource })?.id {
                Divider()
                    .background(RouterTheme.nodeBorder.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)

                Text("Quick Setup")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)

                Button(action: { audioManager.setDefaultOutputDevice(sinkID) }) {
                    Label("Route system output → BlackHole Sink",
                          systemImage: "arrow.right.circle")
                        .font(.system(size: 11))
                        .foregroundColor(RouterTheme.blackHoleSinkColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 3)

                Button(action: { audioManager.setDefaultInputDevice(sourceID) }) {
                    Label("Route system input ← BlackHole Source",
                          systemImage: "arrow.left.circle")
                        .font(.system(size: 11))
                        .foregroundColor(RouterTheme.blackHoleSourceColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
            }
        }
    }

    private func defaultRow(icon: String, iconColor: Color,
                             label: String, deviceID: AudioObjectID?) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(iconColor)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            if let id = deviceID, let dev = audioManager.devices.first(where: { $0.id == id }) {
                Text(dev.name)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            } else {
                Text("None")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    // MARK: - Connection Rows

    private func connectionRow(_ conn: RoutingConnection) -> some View {
        let srcLabel = nodeLabel(conn.source)
        let dstLabel = nodeLabel(conn.destination)
        let isLive   = routingEngine.activeConnectionIDs.contains(conn.id)

        return HStack(spacing: 6) {
            Image(systemName: isLive ? "dot.radiowaves.right" : "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(isLive ? .green : RouterTheme.nodeSelected)
            Text(srcLabel)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(RouterTheme.nodeSelected.opacity(0.6))
            Text(dstLabel)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
            Spacer()
            Button(action: {
                routingEngine.deactivateConnection(connectionID: conn.id)
                routingGraph.removeConnection(conn)
            }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private func inferredConnectionRow(_ conn: RoutingConnection) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.25))
            Text(nodeLabel(conn.source))
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.2))
            Text(nodeLabel(conn.destination))
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(color)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func nodeLabel(_ nodeID: RoutingNodeID) -> String {
        switch nodeID {
        case .device(let id):
            return audioManager.devices.first(where: { $0.id == id })?.name ?? "Device \(id)"
        case .process(let id):
            return processManager.audioProcesses.first(where: { $0.id == id })?.appName ?? "App \(id)"
        }
    }
}
