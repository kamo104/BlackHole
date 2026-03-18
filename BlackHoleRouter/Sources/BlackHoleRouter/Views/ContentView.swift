import SwiftUI
import CoreAudio

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var audioManager: AudioManager
    @StateObject private var graphState = GraphState()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            SidebarView(audioManager: audioManager, graphState: graphState)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        EmptyView()
                    }
                }
        } detail: {
            // Main graph area
            ZStack(alignment: .topTrailing) {
                GraphView(audioManager: audioManager, graphState: graphState)

                // Floating toolbar
                VStack(spacing: 8) {
                    toolbarButton(icon: "arrow.clockwise",
                                  tooltip: "Refresh Devices") {
                        audioManager.refresh()
                    }
                    toolbarButton(icon: "arrow.up.left.and.down.right.magnifyingglass",
                                  tooltip: "Auto Layout") {
                        autoLayout()
                    }
                    toolbarButton(icon: "trash",
                                  tooltip: "Clear User Connections") {
                        graphState.connections.removeAll { !$0.isSystemDefault }
                    }
                    Divider()
                        .frame(width: 24)
                        .background(RouterTheme.nodeBorder)
                    toolbarButton(icon: "sidebar.right",
                                  tooltip: "Inspector") {
                        showInspector.toggle()
                    }
                }
                .padding(10)
                .background(RouterTheme.nodeBG.opacity(0.9))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(RouterTheme.nodeBorder, lineWidth: 1)
                )
                .padding(16)

                // Inspector panel
                if showInspector, let selectedID = graphState.selectedDeviceID,
                   let device = audioManager.devices.first(where: { $0.id == selectedID }) {
                    InspectorPanel(
                        device: device,
                        audioManager: audioManager,
                        onClose: { showInspector = false }
                    )
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
            let layout = NodeLayout.autoLayout(devices: audioManager.devices)
            for (id, pos) in layout {
                graphState.setPosition(pos, for: id)
            }
        }
    }
}

// MARK: - InspectorPanel

struct InspectorPanel: View {
    let device: AudioDeviceModel
    @ObservedObject var audioManager: AudioManager
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Inspector")
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

            Divider().background(RouterTheme.nodeBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Device info
                    inspectorSection("Device") {
                        inspectorRow("Name", device.name)
                        inspectorRow("ID", "\(device.id)")
                        inspectorRow("UID", device.uid)
                        inspectorRow("Type", device.typeLabel)
                    }

                    inspectorSection("Audio") {
                        inspectorRow("Sample Rate", formatSR(device.sampleRate))
                        if device.hasOutput {
                            inspectorRow("Output Channels", "\(device.outputChannels)")
                        }
                        if device.hasInput {
                            inspectorRow("Input Channels", "\(device.inputChannels)")
                        }
                    }

                    // Actions
                    inspectorSection("Actions") {
                        if device.hasOutput {
                            actionButton(
                                "Set as Default Output",
                                icon: "speaker.wave.2",
                                color: RouterTheme.outputDeviceColor,
                                isActive: audioManager.defaultOutputDeviceID == device.id
                            ) {
                                audioManager.setDefaultOutputDevice(device.id)
                            }
                        }
                        if device.hasInput {
                            actionButton(
                                "Set as Default Input",
                                icon: "mic",
                                color: RouterTheme.inputDeviceColor,
                                isActive: audioManager.defaultInputDeviceID == device.id
                            ) {
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(RouterTheme.nodeBorder, lineWidth: 1)
        )
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func inspectorSection<Content: View>(_ title: String,
                                                  @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
            content()
        }
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
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

    private func actionButton(_ title: String, icon: String, color: Color,
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

    private func formatSR(_ rate: Double) -> String {
        rate >= 1000 ? String(format: "%.1f kHz", rate / 1000) : String(format: "%.0f Hz", rate)
    }
}
