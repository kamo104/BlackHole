import Foundation
import CoreAudio
import AppKit

// MARK: - ProcessAudioManager

/// Enumerates running applications that are actively producing or consuming audio.
///
/// On macOS 14+, this uses the CoreAudio `kAudioHardwarePropertyProcessObjectList` API
/// to get accurate, real-time per-process information.
/// On earlier systems the list is empty and the user sees only device nodes.
final class ProcessAudioManager: ObservableObject {

    @Published var audioProcesses: [AppStreamModel] = []

    private var listenerInstalled = false

    init() {
        refresh()
        if #available(macOS 14.0, *) {
            installProcessListListener()
        }
    }

    deinit {
        if #available(macOS 14.0, *), listenerInstalled {
            removeProcessListListener()
        }
    }

    // MARK: - Public

    func refresh() {
        if #available(macOS 14.0, *) {
            let procs = fetchAllProcesses()
            DispatchQueue.main.async { self.audioProcesses = procs }
        }
    }

    // MARK: - Process Enumeration (macOS 14+)

    @available(macOS 14.0, *)
    private func fetchAllProcesses() -> [AppStreamModel] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &objectIDs) == noErr else { return [] }

        return objectIDs.compactMap { buildModel(processObjectID: $0) }
    }

    @available(macOS 14.0, *)
    private func buildModel(processObjectID: AudioObjectID) -> AppStreamModel? {
        let isOutput = getBoolProperty(processObjectID, kAudioProcessPropertyIsRunningOutput)
        let isInput  = getBoolProperty(processObjectID, kAudioProcessPropertyIsRunningInput)
        guard isOutput || isInput else { return nil }   // silent process — skip

        let pid = getPID(processObjectID)
        let outputUIDs = getDeviceUIDs(processObjectID, scope: kAudioObjectPropertyScopeOutput)
        let inputUIDs  = getDeviceUIDs(processObjectID, scope: kAudioObjectPropertyScopeInput)

        var appName  = "PID \(pid)"
        var bundleID = ""
        var icon: NSImage?

        if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
            appName  = app.localizedName ?? appName
            bundleID = app.bundleIdentifier ?? ""
            icon     = app.icon
        }

        return AppStreamModel(
            id: processObjectID,
            pid: pid,
            appName: appName,
            bundleID: bundleID,
            isRunningOutput: isOutput,
            isRunningInput: isInput,
            outputDeviceUIDs: outputUIDs,
            inputDeviceUIDs: inputUIDs,
            icon: icon,
            position: .zero)
    }

    // MARK: - CoreAudio Helpers (macOS 14+)

    @available(macOS 14.0, *)
    private func getPID(_ objectID: AudioObjectID) -> pid_t {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &value)
        return value
    }

    @available(macOS 14.0, *)
    private func getBoolProperty(_ objectID: AudioObjectID,
                                 _ selector: AudioObjectPropertySelector) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &value)
        return value != 0
    }

    /// Returns the UIDs of every device the process is currently using for the given scope.
    @available(macOS 14.0, *)
    private func getDeviceUIDs(_ processObjectID: AudioObjectID,
                               scope: AudioObjectPropertyScope) -> [String] {
        // kAudioProcessPropertyDevices – array of AudioObjectID for devices used by this process
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyDevices,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(processObjectID, &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(processObjectID, &addr, 0, nil, &size, &deviceIDs) == noErr
        else { return [] }

        return deviceIDs.compactMap { deviceUID(for: $0) }
    }

    private func deviceUID(for deviceID: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfUID: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &cfUID) == noErr
        else { return nil }
        return cfUID as String
    }

    // MARK: - Property Listener

    @available(macOS 14.0, *)
    private func installProcessListListener() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, DispatchQueue.main, processListListenerBlock)
        listenerInstalled = true
    }

    @available(macOS 14.0, *)
    private func removeProcessListListener() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, DispatchQueue.main, processListListenerBlock)
    }

    private lazy var processListListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refresh()
    }
}
