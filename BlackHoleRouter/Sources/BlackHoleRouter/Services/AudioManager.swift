import Foundation
import CoreAudio
import CoreFoundation

// MARK: - AudioManager

final class AudioManager: ObservableObject {
    @Published var devices: [AudioDeviceModel] = []
    @Published var defaultOutputDeviceID: AudioObjectID?
    @Published var defaultInputDeviceID: AudioObjectID?

    init() {
        refresh()
        setupListeners()
    }

    deinit {
        removeListeners()
    }

    // MARK: - Public Interface

    func refresh() {
        let rawDevices = fetchAllDevices()
        DispatchQueue.main.async {
            self.devices = rawDevices
            self.defaultOutputDeviceID = self.getDefaultOutputDevice()
            self.defaultInputDeviceID = self.getDefaultInputDevice()
        }
    }

    func setDefaultOutputDevice(_ deviceID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &id
        )
        if status == noErr {
            DispatchQueue.main.async {
                self.defaultOutputDeviceID = deviceID
            }
        }
    }

    func setDefaultInputDevice(_ deviceID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &id
        )
        if status == noErr {
            DispatchQueue.main.async {
                self.defaultInputDeviceID = deviceID
            }
        }
    }

    // MARK: - Device Enumeration

    private func fetchAllDevices() -> [AudioDeviceModel] {
        let deviceIDs = getAllDeviceIDs()
        return deviceIDs.map { makeAudioDevice(id: $0) }
            .filter { !$0.name.isEmpty }
    }

    private func getAllDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return [] }
        return deviceIDs
    }

    private func makeAudioDevice(id: AudioObjectID) -> AudioDeviceModel {
        let name = getDeviceName(id)
        let uid = getDeviceUID(id)
        let hasInput = getStreamCount(id: id, scope: kAudioObjectPropertyScopeInput) > 0
        let hasOutput = getStreamCount(id: id, scope: kAudioObjectPropertyScopeOutput) > 0
        let sampleRate = getSampleRate(id)
        let inputChannels = getChannelCount(id: id, scope: kAudioObjectPropertyScopeInput)
        let outputChannels = getChannelCount(id: id, scope: kAudioObjectPropertyScopeOutput)

        // Detect BlackHole Sink/Source by name patterns
        let lowerName = name.lowercased()
        let isBlackHole = lowerName.contains("blackhole")
        let isBlackHoleSink = isBlackHole && (lowerName.contains("sink") || (isBlackHole && hasOutput && !hasInput))
        let isBlackHoleSource = isBlackHole && (lowerName.contains("source") || (isBlackHole && hasInput && !hasOutput))

        return AudioDeviceModel(
            id: id,
            name: name,
            uid: uid,
            hasInput: hasInput,
            hasOutput: hasOutput,
            sampleRate: sampleRate,
            inputChannels: inputChannels,
            outputChannels: outputChannels,
            position: .zero,
            isBlackHoleSink: isBlackHoleSink,
            isBlackHoleSource: isBlackHoleSource
        )
    }

    // MARK: - CoreAudio Helpers

    private func getDeviceName(_ deviceID: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr else { return "" }
        return name as String
    }

    private func getDeviceUID(_ deviceID: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr else { return "" }
        return uid as String
    }

    private func getStreamCount(id deviceID: AudioObjectID,
                                scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private func getChannelCount(id deviceID: AudioObjectID,
                                 scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else { return 0 }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferList.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList)
        guard status == noErr else { return 0 }

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        return abl.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func getSampleRate(_ deviceID: AudioObjectID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
        guard status == noErr else { return 0 }
        return rate
    }

    func getDefaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    func getDefaultInputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    // MARK: - Property Listeners

    private func setupListeners() {
        addDevicesListener()
        addDefaultOutputListener()
        addDefaultInputListener()
    }

    private func removeListeners() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            deviceListenerBlock
        )

        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputAddress,
            DispatchQueue.main,
            defaultOutputListenerBlock
        )

        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputAddress,
            DispatchQueue.main,
            defaultInputListenerBlock
        )
    }

    private lazy var deviceListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refresh()
    }

    private lazy var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self = self else { return }
        DispatchQueue.main.async {
            self.defaultOutputDeviceID = self.getDefaultOutputDevice()
        }
    }

    private lazy var defaultInputListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self = self else { return }
        DispatchQueue.main.async {
            self.defaultInputDeviceID = self.getDefaultInputDevice()
        }
    }

    private func addDevicesListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            deviceListenerBlock
        )
    }

    private func addDefaultOutputListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            defaultOutputListenerBlock
        )
    }

    private func addDefaultInputListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            defaultInputListenerBlock
        )
    }
}
