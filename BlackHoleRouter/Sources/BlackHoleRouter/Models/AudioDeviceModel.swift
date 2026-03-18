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

// MARK: - PortSide

enum PortSide {
    case input   // Left side of node - audio enters the node here
    case output  // Right side of node - audio leaves the node here
}
