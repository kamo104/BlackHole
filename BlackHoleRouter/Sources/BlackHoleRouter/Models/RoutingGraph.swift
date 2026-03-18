import Foundation
import CoreAudio
import CoreGraphics
import Combine

// MARK: - RoutingNodeID

/// Uniquely identifies a node in the routing graph.
/// A node can be either an audio device or an application process stream.
enum RoutingNodeID: Hashable, Equatable {
    /// A CoreAudio device (physical or virtual).
    case device(AudioObjectID)
    /// A running application's audio stream (CoreAudio process object ID).
    case process(AudioObjectID)
}

// MARK: - RoutingConnection

/// A directed audio connection from one routing node to another.
struct RoutingConnection: Identifiable, Equatable {
    let id: UUID
    /// The node producing audio (output port).
    let source: RoutingNodeID
    /// The node consuming audio (input port).
    let destination: RoutingNodeID
    /// Whether an `AudioHardwareCreateProcessTap` + AVAudioEngine route is live.
    var isActive: Bool
    /// Derived from the BlackHole driver's internal Sink→Source ring buffer.
    var isBlackHoleInternal: Bool
    /// Inferred from the app's current device selection (not user-drawn).
    var isInferred: Bool

    init(source: RoutingNodeID,
         destination: RoutingNodeID,
         isActive: Bool = false,
         isBlackHoleInternal: Bool = false,
         isInferred: Bool = false) {
        self.id = UUID()
        self.source = source
        self.destination = destination
        self.isActive = isActive
        self.isBlackHoleInternal = isBlackHoleInternal
        self.isInferred = isInferred
    }

    static func == (lhs: RoutingConnection, rhs: RoutingConnection) -> Bool { lhs.id == rhs.id }
}

// MARK: - RoutingGraph

/// Central store for the entire node-graph state: positions, connections, and interaction state.
/// This is the macOS equivalent of the PipeWire graph that qpwgraph visualises.
final class RoutingGraph: ObservableObject {

    // MARK: Published state

    @Published var connections: [RoutingConnection] = []
    @Published var nodePositions: [RoutingNodeID: CGPoint] = [:]
    @Published var selectedNodeID: RoutingNodeID?

    /// The node whose output port was tapped first — a wire is being drawn.
    @Published var pendingSourceNodeID: RoutingNodeID?
    /// Current cursor position while a wire is being dragged (canvas coordinates).
    @Published var pendingWireEnd: CGPoint?

    // MARK: - Node Positions

    func setPosition(_ position: CGPoint, for nodeID: RoutingNodeID) {
        nodePositions[nodeID] = position
    }

    func getPosition(for nodeID: RoutingNodeID) -> CGPoint {
        nodePositions[nodeID] ?? CGPoint(x: 400, y: 300)
    }

    // MARK: - Connection Management

    @discardableResult
    func addConnection(from source: RoutingNodeID,
                       to destination: RoutingNodeID,
                       isBlackHoleInternal: Bool = false,
                       isInferred: Bool = false) -> RoutingConnection? {
        guard !connections.contains(where: { $0.source == source && $0.destination == destination })
        else { return nil }
        let conn = RoutingConnection(
            source: source,
            destination: destination,
            isActive: false,
            isBlackHoleInternal: isBlackHoleInternal,
            isInferred: isInferred
        )
        connections.append(conn)
        return conn
    }

    func removeConnection(_ connection: RoutingConnection) {
        connections.removeAll { $0.id == connection.id }
    }

    func removeUserConnections() {
        connections.removeAll { !$0.isBlackHoleInternal && !$0.isInferred }
    }

    func removeInferredConnections() {
        connections.removeAll { $0.isInferred }
    }

    func removeBlackHoleInternalConnections() {
        connections.removeAll { $0.isBlackHoleInternal }
    }

    func markConnectionActive(_ id: UUID, active: Bool) {
        guard let idx = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[idx].isActive = active
    }

    // MARK: - Pending Connection Interaction

    func startPendingConnection(from nodeID: RoutingNodeID) {
        pendingSourceNodeID = nodeID
        pendingWireEnd = nil
    }

    func cancelPendingConnection() {
        pendingSourceNodeID = nil
        pendingWireEnd = nil
    }

    /// Complete the pending wire. Returns the new connection if one was added.
    @discardableResult
    func completePendingConnection(to destinationNodeID: RoutingNodeID) -> RoutingConnection? {
        guard let sourceID = pendingSourceNodeID, sourceID != destinationNodeID else {
            cancelPendingConnection()
            return nil
        }
        let conn = addConnection(from: sourceID, to: destinationNodeID)
        cancelPendingConnection()
        return conn
    }

    // MARK: - Bulk Refresh of Inferred Connections

    /// Re-derives inferred connections from the current device+process state.
    /// Called whenever AudioManager or ProcessAudioManager reports changes.
    func refreshInferredConnections(apps: [AppStreamModel],
                                    devices: [AudioDeviceModel]) {
        removeInferredConnections()
        removeBlackHoleInternalConnections()

        // App → Device (app is currently playing audio to that device)
        for app in apps where app.isRunningOutput {
            for uid in app.outputDeviceUIDs {
                if let dev = devices.first(where: { $0.uid == uid }) {
                    addConnection(from: .process(app.id), to: .device(dev.id), isInferred: true)
                }
            }
        }

        // Device → App (app is currently recording from that device)
        for app in apps where app.isRunningInput {
            for uid in app.inputDeviceUIDs {
                if let dev = devices.first(where: { $0.uid == uid }) {
                    addConnection(from: .device(dev.id), to: .process(app.id), isInferred: true)
                }
            }
        }

        // BlackHole internal Sink → Source (ring-buffer coupling)
        let sinks = devices.filter { $0.isBlackHoleSink }
        let sources = devices.filter { $0.isBlackHoleSource }
        for sink in sinks {
            for source in sources {
                addConnection(from: .device(sink.id), to: .device(source.id),
                              isBlackHoleInternal: true)
            }
        }
    }
}
