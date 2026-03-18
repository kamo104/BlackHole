import SwiftUI
import CoreAudio

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var processManager: ProcessAudioManager
    @EnvironmentObject var routingEngine: RoutingEngine
    @StateObject private var routingGraph = RoutingGraph()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                audioManager: audioManager,
                processManager: processManager,
                routingGraph: routingGraph,
                routingEngine: routingEngine)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
            .toolbar {
                ToolbarItem(placement: .navigation) { EmptyView() }
            }
        } detail: {
            ZStack(alignment: .topTrailing) {
                GraphView(
                    audioManager: audioManager,
                    processManager: processManager,
                    routingGraph: routingGraph,
                    routingEngine: routingEngine)

                // Floating toolbar
                VStack(spacing: 8) {
                    toolbarButton(icon: "arrow.clockwise",
                                  tooltip: "Refresh Devices & Apps") {
                        audioManager.refresh()
                        processManager.refresh()
                    }
                    toolbarButton(icon: "arrow.up.left.and.down.right.magnifyingglass",
                                  tooltip: "Auto Layout") { autoLayout() }
                    toolbarButton(icon: "trash",
                                  tooltip: "Clear User Connections") { clearUserConnections() }
                    Divider()
                        .frame(width: 24)
                        .background(RouterTheme.nodeBorder)
                    toolbarButton(icon: "sidebar.right",
                                  tooltip: "Inspector") { showInspector.toggle() }
                }
                .padding(10)
                .background(RouterTheme.nodeBG.opacity(0.9))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(RouterTheme.nodeBorder, lineWidth: 1))
                .padding(16)

                // Inspector panel
                if showInspector {
                    inspectorPanel
                        .frame(width: 240)
                        .transition(.move(edge: .trailing))
                        .animation(.easeInOut, value: showInspector)
                }
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundColor(RouterTheme.blackHoleSinkColor)
                    Text("BlackHole Router")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .background(RouterTheme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorPanel: some View {
        switch routingGraph.selectedNodeID {
        case .device(let id):
            if let device = audioManager.devices.first(where: { $0.id == id }) {
                DeviceInspectorPanel(
                    device: device,
                    audioManager: audioManager,
                    onClose: { showInspector = false })
            } else {
                EmptyView()
            }
        case .process(let id):
            if let app = processManager.audioProcesses.first(where: { $0.id == id }) {
                AppInspectorPanel(
                    app: app,
                    routingGraph: routingGraph,
                    routingEngine: routingEngine,
                    onClose: { showInspector = false })
            } else {
                EmptyView()
            }
        case nil:
            EmptyView()
        }
    }

    // MARK: - Toolbar Actions

    private func toolbarButton(icon: String, tooltip: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func autoLayout() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            let layout = NodeLayout.autoLayout(devices: audioManager.devices,
                                               apps: processManager.audioProcesses)
            for (id, pos) in layout { routingGraph.setPosition(pos, for: id) }
        }
    }

    private func clearUserConnections() {
        for conn in routingGraph.connections
        where !conn.isInferred && !conn.isBlackHoleInternal {
            routingEngine.deactivateConnection(connectionID: conn.id)
        }
        routingGraph.removeUserConnections()
    }
}

// MARK: - DeviceInspectorPanel

struct DeviceInspectorPanel: View {
    let device: AudioDeviceModel
    @ObservedObject var audioManager: AudioManager
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inspectorHeader("Device Inspector")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    inspectorSection("Device") {
                        inspectorRow("Name", device.name)
                        inspectorRow("ID",   "\(device.id)")
                        inspectorRow("UID",  device.uid)
                        inspectorRow("Type", device.typeLabel)
                    }
                    inspectorSection("Audio") {
                        inspectorRow("Sample Rate", formatSR(device.sampleRate))
                        if device.hasOutput {
                            inspectorRow("Out Channels", "\(device.outputChannels)")
                        }
                        if device.hasInput {
                            inspectorRow("In Channels", "\(device.inputChannels)")
                        }
                    }
                    inspectorSection("Actions") {
                        if device.hasOutput {
                            actionButton("Set as Default Output",
                                         icon: "speaker.wave.2",
                                         color: RouterTheme.outputDeviceColor,
                                         isActive: audioManager.defaultOutputDeviceID == device.id) {
                                audioManager.setDefaultOutputDevice(device.id)
                            }
                        }
                        if device.hasInput {
                            actionButton("Set as Default Input",
                                         icon: "mic",
                                         color: RouterTheme.inputDeviceColor,
                                         isActive: audioManager.defaultInputDeviceID == device.id) {
                                audioManager.setDefaultInputDevice(device.id)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color(red: 0.14, green: 0.14, blue: 0.18))
        .cornerRadius(12, corners: [.bottomLeft, .topLeft])
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(RouterTheme.nodeBorder, lineWidth: 1))
        .padding(.vertical, 8)
    }

    private func inspectorHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RouterTheme.nodeBG)
    }
}

// MARK: - AppInspectorPanel

struct AppInspectorPanel: View {
    let app: AppStreamModel
    @ObservedObject var routingGraph: RoutingGraph
    @ObservedObject var routingEngine: RoutingEngine
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inspectorHeader("App Inspector")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    inspectorSection("Application") {
                        inspectorRow("Name",      app.appName)
                        inspectorRow("PID",       "\(app.pid)")
                        inspectorRow("Bundle",    app.bundleID)
                        inspectorRow("Playing",   app.isRunningOutput ? "Yes" : "No")
                        inspectorRow("Recording", app.isRunningInput  ? "Yes" : "No")
                    }

                    if !app.outputDeviceUIDs.isEmpty {
                        inspectorSection("Output Devices") {
                            ForEach(app.outputDeviceUIDs, id: \.self) { uid in
                                inspectorRow("UID", uid)
                            }
                        }
                    }

                    if !app.inputDeviceUIDs.isEmpty {
                        inspectorSection("Input Devices") {
                            ForEach(app.inputDeviceUIDs, id: \.self) { uid in
                                inspectorRow("UID", uid)
                            }
                        }
                    }

                    // Active routes from this app
                    let appConns = routingGraph.connections.filter {
                        $0.source == .process(app.id) && !$0.isInferred
                    }
                    if !appConns.isEmpty {
                        inspectorSection("Active Routes") {
                            ForEach(appConns) { conn in
                                HStack {
                                    Image(systemName: routingEngine.activeConnectionIDs.contains(conn.id)
                                          ? "dot.radiowaves.right" : "minus.circle")
                                        .font(.system(size: 10))
                                        .foregroundColor(
                                            routingEngine.activeConnectionIDs.contains(conn.id)
                                            ? .green : .white.opacity(0.4))
                                    if case .device(let devID) = conn.destination {
                                        Text("→ device \(devID)")
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
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
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color(red: 0.14, green: 0.14, blue: 0.18))
        .cornerRadius(12, corners: [.bottomLeft, .topLeft])
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(RouterTheme.nodeBorder, lineWidth: 1))
        .padding(.vertical, 8)
    }

    private func inspectorHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RouterTheme.nodeBG)
    }
}

// MARK: - Shared Inspector Helpers (via extension so both panels can reuse them)

extension View {
    func inspectorSection<C: View>(_ title: String,
                                   @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
            content()
        }
    }

    func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.trailing)
        }
    }

    func actionButton(_ title: String, icon: String, color: Color,
                      isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11))
                .foregroundColor(isActive ? .black : color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isActive ? color : color.opacity(0.15))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    func formatSR(_ rate: Double) -> String {
        rate >= 1000 ? String(format: "%.1f kHz", rate / 1000) : String(format: "%.0f Hz", rate)
    }
}
