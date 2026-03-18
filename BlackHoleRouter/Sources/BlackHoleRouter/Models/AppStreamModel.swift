import Foundation
import CoreAudio
import CoreGraphics
import AppKit

// MARK: - AppStreamModel

/// Represents a single running application that is actively sending or receiving audio.
/// Each instance is a node in the routing graph — the macOS equivalent of a PipeWire client node.
struct AppStreamModel: Identifiable, Hashable {
    /// CoreAudio process object ID (`kAudioHardwarePropertyProcessObjectList`).
    let id: AudioObjectID
    /// Unix PID — used to look up NSRunningApplication for name and icon.
    let pid: pid_t
    var appName: String
    var bundleID: String
    /// True when the app is actively rendering audio output (playing).
    var isRunningOutput: Bool
    /// True when the app is actively capturing audio input (recording).
    var isRunningInput: Bool
    /// UIDs of devices this process is currently sending output to.
    var outputDeviceUIDs: [String]
    /// UIDs of devices this process is currently receiving input from.
    var inputDeviceUIDs: [String]
    /// App icon for the node header.
    var icon: NSImage?
    /// Canvas position — set by auto-layout or user drag.
    var position: CGPoint

    // MARK: - Convenience

    /// True if the app is currently routing its output through any BlackHole device.
    var isUsingBlackHoleSink: Bool {
        isRunningOutput && outputDeviceUIDs.contains { $0.localizedCaseInsensitiveContains("blackhole") }
    }

    /// True if the app is currently recording from any BlackHole device.
    var isUsingBlackHoleSource: Bool {
        isRunningInput && inputDeviceUIDs.contains { $0.localizedCaseInsensitiveContains("blackhole") }
    }

    static func == (lhs: AppStreamModel, rhs: AppStreamModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
