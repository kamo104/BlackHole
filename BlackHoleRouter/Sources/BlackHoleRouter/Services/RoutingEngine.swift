import Foundation
import CoreAudio
import AVFoundation

// MARK: - RoutingEngine

/// Manages active per-app audio routing using CoreAudio Process Audio Taps.
///
/// **How it works (macOS 14.2+):**
/// 1. When the user draws a connection from an App node to a Device node,
///    `activateConnection` is called.
/// 2. `AudioHardwareCreateProcessTap` creates a real-time tap on the app's audio output stream.
///    This captures the app's audio *before* it is mixed into any device ring buffer —
///    the same way PipeWire routes individual client streams on Linux.
/// 3. An `AVAudioEngine` instance reads from the tap and writes to the destination device.
/// 4. `deactivateConnection` tears down the engine and destroys the tap.
///
/// **Fallback (< macOS 14.2):**
/// The graph is shown visually but no active audio tap is started.
/// The user can still see which apps are using which devices (inferred connections)
/// and set system defaults from the sidebar.
final class RoutingEngine: ObservableObject {

    // MARK: - Types

    enum RoutingError: LocalizedError {
        case tapCreationFailed(OSStatus)
        case engineSetupFailed(OSStatus)
        case unsupportedPlatform

        var errorDescription: String? {
            switch self {
            case .tapCreationFailed(let s):  return "Process tap creation failed (OSStatus \(s))"
            case .engineSetupFailed(let s):  return "AVAudioEngine setup failed (OSStatus \(s))"
            case .unsupportedPlatform:
                return "Process Audio Tap routing requires macOS 14.2 or later. " +
                       "The graph connection is shown visually; ensure the app uses " +
                       "the correct BlackHole device in its own audio preferences."
            }
        }
    }

    private struct TapRoute {
        let tapID: AudioObjectID
        let engine: AVAudioEngine
    }

    // MARK: - Published State

    @Published var lastError: String?
    /// Connection IDs that are currently being routed via a live process tap.
    @Published var activeConnectionIDs: Set<UUID> = []

    // MARK: - Private

    private var routes: [UUID: TapRoute] = [:]

    // MARK: - Public Interface

    /// Start active audio routing for a user-drawn connection.
    /// - Parameters:
    ///   - source: Must be `.process(processObjectID)`.
    ///   - destination: Must be `.device(deviceID)`.
    ///   - connectionID: The `RoutingConnection.id` to mark as active.
    func activateConnection(source: RoutingNodeID,
                            destination: RoutingNodeID,
                            connectionID: UUID) {
        guard case .process(let processObjectID) = source,
              case .device(let deviceID) = destination else {
            // Device→Device or Device→Process connections don't need a tap.
            return
        }

        guard #available(macOS 14.2, *) else {
            lastError = RoutingError.unsupportedPlatform.errorDescription
            return
        }

        do {
            let route = try startTapRoute(processObjectID: processObjectID, destDeviceID: deviceID)
            routes[connectionID] = route
            DispatchQueue.main.async {
                self.activeConnectionIDs.insert(connectionID)
                self.lastError = nil
            }
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }
    }

    /// Stop the active audio routing for a connection and tear down the tap.
    func deactivateConnection(connectionID: UUID) {
        guard let route = routes.removeValue(forKey: connectionID) else { return }
        route.engine.stop()
        if #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(route.tapID)
        }
        DispatchQueue.main.async {
            self.activeConnectionIDs.remove(connectionID)
        }
    }

    /// Stop all active routes (called on quit or "Clear" action).
    func deactivateAll() {
        for (id, route) in routes {
            route.engine.stop()
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(route.tapID)
            }
            DispatchQueue.main.async { self.activeConnectionIDs.remove(id) }
        }
        routes.removeAll()
    }

    // MARK: - Process Tap + AVAudioEngine Setup (macOS 14.2+)

    @available(macOS 14.2, *)
    private func startTapRoute(processObjectID: AudioObjectID,
                               destDeviceID: AudioObjectID) throws -> TapRoute {
        // ── Step 1: Create the process tap ──────────────────────────────────────────
        // `CATapDescription` tells CoreAudio which processes to tap and how to mix them.
        // `stereoMixdownOfProcesses:` produces a stereo mix of all streams from the process.
        let tapDescription = CATapDescription(
            stereoMixdownOfProcesses: [NSNumber(value: processObjectID)])
        var tapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard tapStatus == noErr else { throw RoutingError.tapCreationFailed(tapStatus) }

        // ── Step 2: Get the tap's audio format ──────────────────────────────────────
        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &asbdSize, &asbd)

        let channelCount = asbd.mChannelsPerFrame > 0 ? AVAudioChannelCount(asbd.mChannelsPerFrame) : 2
        let sampleRate   = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48_000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                         channels: channelCount)
        else { throw RoutingError.engineSetupFailed(kAudioUnitErr_InvalidParameter) }

        // ── Step 3: Wire up AVAudioEngine ───────────────────────────────────────────
        // The tap object ID doubles as the CoreAudio device ID for the virtual tap device.
        let engine = AVAudioEngine()

        // Point the engine's input at the tap device.
        var tapDeviceID = tapID
        let inputStatus = AudioUnitSetProperty(
            engine.inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0, &tapDeviceID,
            UInt32(MemoryLayout<AudioObjectID>.size))
        guard inputStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw RoutingError.engineSetupFailed(inputStatus)
        }

        // Point the engine's output at the destination device.
        var destID = destDeviceID
        let outputStatus = AudioUnitSetProperty(
            engine.outputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0, &destID,
            UInt32(MemoryLayout<AudioObjectID>.size))
        guard outputStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw RoutingError.engineSetupFailed(outputStatus)
        }

        // Simple pass-through: input → mixer → output
        engine.connect(engine.inputNode, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode,
                       format: engine.outputNode.outputFormat(forBus: 0))

        try engine.start()
        return TapRoute(tapID: tapID, engine: engine)
    }
}
