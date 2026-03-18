import Foundation
import CoreAudio
import CoreGraphics
import Combine

// MARK: - AudioDeviceModel

struct AudioDeviceModel: Identifiable, Hashable {
    let id: AudioObjectID
    var name: String
    var uid: String
    var hasInput: Bool
    var hasOutput: Bool
    var sampleRate: Double
    var inputChannels: Int
    var outputChannels: Int
    var position: CGPoint

    // BlackHole classification
    var isBlackHoleSink: Bool
    var isBlackHoleSource: Bool

    var isBlackHole: Bool { isBlackHoleSink || isBlackHoleSource }

    var typeLabel: String {
        if isBlackHoleSink { return "Sink" }
        if isBlackHoleSource { return "Source" }
        if hasInput && hasOutput { return "Input/Output" }
        if hasInput { return "Input" }
        if hasOutput { return "Output" }
        return "Unknown"
    }

    static func == (lhs: AudioDeviceModel, rhs: AudioDeviceModel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - AudioConnectionModel

struct AudioConnectionModel: Identifiable, Equatable {
    let id: UUID
    let sourceDeviceID: AudioObjectID
    let destinationDeviceID: AudioObjectID
    var isSystemDefault: Bool

    init(sourceDeviceID: AudioObjectID,
         destinationDeviceID: AudioObjectID,
         isSystemDefault: Bool = false) {
        self.id = UUID()
        self.sourceDeviceID = sourceDeviceID
        self.destinationDeviceID = destinationDeviceID
        self.isSystemDefault = isSystemDefault
    }
}

// MARK: - PortModel

enum PortSide {
    case input   // Left side of node - audio enters the device here
    case output  // Right side of node - audio leaves the device here
}

struct PortModel: Identifiable {
    let id: UUID
    let deviceID: AudioObjectID
    let side: PortSide
    var label: String

    init(deviceID: AudioObjectID, side: PortSide, label: String = "") {
        self.id = UUID()
        self.deviceID = deviceID
        self.side = side
        self.label = label
    }
}

// MARK: - GraphState

final class GraphState: ObservableObject {
    @Published var nodePositions: [AudioObjectID: CGPoint] = [:]
    @Published var connections: [AudioConnectionModel] = []
    @Published var selectedDeviceID: AudioObjectID?
    @Published var pendingConnectionSourceID: AudioObjectID?
    @Published var pendingConnectionSide: PortSide?

    func setPosition(_ position: CGPoint, for deviceID: AudioObjectID) {
        nodePositions[deviceID] = position
    }

    func getPosition(for deviceID: AudioObjectID) -> CGPoint {
        nodePositions[deviceID] ?? .zero
    }

    func addConnection(from sourceID: AudioObjectID,
                       to destinationID: AudioObjectID,
                       isSystemDefault: Bool = false) {
        // Avoid duplicates
        let exists = connections.contains {
            $0.sourceDeviceID == sourceID && $0.destinationDeviceID == destinationID
        }
        if !exists {
            connections.append(AudioConnectionModel(
                sourceDeviceID: sourceID,
                destinationDeviceID: destinationID,
                isSystemDefault: isSystemDefault
            ))
        }
    }

    func removeConnection(_ connection: AudioConnectionModel) {
        connections.removeAll { $0.id == connection.id }
    }

    func removeAllSystemDefaultConnections() {
        connections.removeAll { $0.isSystemDefault }
    }
}
