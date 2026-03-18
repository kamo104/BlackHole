import SwiftUI
import CoreAudio

struct SidebarView: View {
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var graphState: GraphState

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

            Divider()
                .background(RouterTheme.nodeBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // BlackHole Devices Section
                    let blackHoleDevices = audioManager.devices.filter { $0.isBlackHole }
                    if !blackHoleDevices.isEmpty {
                        sectionHeader("BlackHole Devices",
                                      icon: "infinity.circle.fill",
                                      color: RouterTheme.blackHoleSinkColor)
                        ForEach(blackHoleDevices) { device in
                            deviceRow(device)
                        }
                    }

                    // System Defaults Section
                    sectionHeader("System Defaults",
                                  icon: "gearshape.fill",
                                  color: RouterTheme.ioDeviceColor)
                    systemDefaultsSection

                    // All Devices Section
                    let regularDevices = audioManager.devices.filter { !$0.isBlackHole }
                    if !regularDevices.isEmpty {
                        sectionHeader("All Audio Devices",
                                      icon: "waveform",
                                      color: RouterTheme.outputDeviceColor)
                        ForEach(regularDevices) { device in
                            deviceRow(device)
                        }
                    }

                    // Active Connections
                    if !graphState.connections.isEmpty {
                        sectionHeader("Active Routing",
                                      icon: "arrow.triangle.branch",
                                      color: RouterTheme.nodeSelected)
                        ForEach(graphState.connections) { conn in
                            connectionRow(conn)
                        }
                    }
                }
                .padding(.bottom, 16)
            }

            Divider()
                .background(RouterTheme.nodeBorder)

            // Bottom bar
            HStack {
                Button(action: { audioManager.refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(RouterTheme.outputDeviceColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Spacer()

                Text("\(audioManager.devices.count) devices")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.trailing, 14)
            }
            .background(RouterTheme.nodeBG)
        }
        .background(Color(red: 0.13, green: 0.13, blue: 0.16))
    }

    // MARK: - Sections

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func deviceRow(_ device: AudioDeviceModel) -> some View {
        let isSelected = graphState.selectedDeviceID == device.id
        let isDefaultOut = audioManager.defaultOutputDeviceID == device.id
        let isDefaultIn = audioManager.defaultInputDeviceID == device.id

        return Button(action: {
            graphState.selectedDeviceID = isSelected ? nil : device.id
        }) {
            HStack(spacing: 8) {
                // Status dot
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

                // Default badges
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

    private var systemDefaultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Output
            HStack {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundColor(RouterTheme.outputDeviceColor)
                    .frame(width: 16)
                Text("Output")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                if let id = audioManager.defaultOutputDeviceID,
                   let dev = audioManager.devices.first(where: { $0.id == id }) {
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

            // Input
            HStack {
                Image(systemName: "mic")
                    .font(.system(size: 11))
                    .foregroundColor(RouterTheme.inputDeviceColor)
                    .frame(width: 16)
                Text("Input")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                if let id = audioManager.defaultInputDeviceID,
                   let dev = audioManager.devices.first(where: { $0.id == id }) {
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

            // Quick routing buttons
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

                Button(action: {
                    audioManager.setDefaultOutputDevice(sinkID)
                }) {
                    Label("Route output → BlackHole Sink",
                          systemImage: "arrow.right.circle")
                        .font(.system(size: 11))
                        .foregroundColor(RouterTheme.blackHoleSinkColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 3)

                Button(action: {
                    audioManager.setDefaultInputDevice(sourceID)
                }) {
                    Label("Route input ← BlackHole Source",
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

    private func connectionRow(_ conn: AudioConnectionModel) -> some View {
        let srcName = audioManager.devices.first(where: { $0.id == conn.sourceDeviceID })?.name ?? "?"
        let dstName = audioManager.devices.first(where: { $0.id == conn.destinationDeviceID })?.name ?? "?"

        return HStack(spacing: 6) {
            Text(srcName)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(conn.isSystemDefault
                                 ? RouterTheme.blackHoleSourceColor
                                 : RouterTheme.nodeSelected)
            Text(dstName)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
            Spacer()
            if !conn.isSystemDefault {
                Button(action: { graphState.removeConnection(conn) }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}
