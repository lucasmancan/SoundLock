import CoreAudio
import Foundation

/// Stateless façade over the CoreAudio HAL property API.
/// Isolates `UnsafeMutablePointer` use to a single file.
enum CoreAudioBridge {

    // MARK: - Transport types considered physical
    private static let physicalTransportTypes: Set<UInt32> = [
        kAudioDeviceTransportTypeBuiltIn,
        kAudioDeviceTransportTypePCI,
        kAudioDeviceTransportTypeUSB,
        kAudioDeviceTransportTypeFireWire,
        kAudioDeviceTransportTypeBluetooth,
        kAudioDeviceTransportTypeBluetoothLE,
        kAudioDeviceTransportTypeHDMI,
        kAudioDeviceTransportTypeDisplayPort,
        kAudioDeviceTransportTypeAirPlay,
        kAudioDeviceTransportTypeAVB,
        kAudioDeviceTransportTypeThunderbolt,
    ]

    // MARK: - Default device

    static func getDefaultDevice(input: Bool) -> AudioDeviceID {
        var deviceID: AudioDeviceID = kAudioDeviceUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        return deviceID
    }

    @discardableResult
    static func setDefaultDevice(_ deviceID: AudioDeviceID, input: Bool) -> OSStatus {
        var id = deviceID
        var addr = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                          UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    }

    // MARK: - Volume

    static func canControlVolume(_ deviceID: AudioDeviceID, input: Bool) -> Bool {
        let scope = scope(input: input)
        for element: AudioObjectPropertyElement in [0, 1] {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            var isSettable: DarwinBoolean = false
            if AudioObjectIsPropertySettable(deviceID, &addr, &isSettable) == noErr, isSettable.boolValue { return true }
        }
        return false
    }

    static func getVolume(_ deviceID: AudioDeviceID, input: Bool) -> Float {
        let scope = scope(input: input)
        for element: AudioObjectPropertyElement in [0, 1] {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            var vol: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol) == noErr { return vol }
        }
        return 1.0
    }

    static func setVolume(_ volume: Float, deviceID: AudioDeviceID, input: Bool) {
        let scope = scope(input: input)
        var vol = volume
        var masterAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: 0)
        var isSettable: DarwinBoolean = false
        if AudioObjectIsPropertySettable(deviceID, &masterAddr, &isSettable) == noErr, isSettable.boolValue {
            AudioObjectSetPropertyData(deviceID, &masterAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
            return
        }
        for ch: AudioObjectPropertyElement in [1, 2] {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: ch)
            AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
        }
    }

    // MARK: - Mute

    static func getMute(_ deviceID: AudioDeviceID, input: Bool) -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope(input: input), mElement: 0)
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value)
        return value == 1
    }

    static func setMute(_ muted: Bool, deviceID: AudioDeviceID, input: Bool) {
        var value: UInt32 = muted ? 1 : 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope(input: input), mElement: 0)
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: - Device enumeration

    /// Single CoreAudio enumeration pass — builds output and input lists from the
    /// same device array to avoid a second kernel round-trip.
    static func enumeratePhysicalDevices() -> (output: [AudioDevice], input: [AudioDevice]) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return ([], []) }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return ([], []) }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return ([], []) }

        var outputs: [AudioDevice] = []
        var inputs:  [AudioDevice] = []
        outputs.reserveCapacity(count)
        inputs.reserveCapacity(count)

        for id in ids {
            guard isPhysicalDevice(id) else { continue }
            let uid  = deviceUID(id)
            let name = deviceName(id)
            if hasChannels(id, input: false) { outputs.append(AudioDevice(id: id, uid: uid, name: name)) }
            if hasChannels(id, input: true)  { inputs.append(AudioDevice(id: id, uid: uid, name: name)) }
        }
        return (outputs, inputs)
    }

    // MARK: - Per-device property helpers

    private static func isPhysicalDevice(_ deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transport) == noErr
        else { return false }
        return physicalTransportTypes.contains(transport)
    }

    private static func hasChannels(_ deviceID: AudioDeviceID, input: Bool) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope(input: input), mElement: 0)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &dataSize) == noErr,
              dataSize >= MemoryLayout<AudioBufferList>.size
        else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize),
                                                    alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &dataSize, raw) == noErr else { return false }
        let bl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        let n  = Int(bl.pointee.mNumberBuffers)
        guard n > 0 else { return false }
        return withUnsafePointer(to: bl.pointee.mBuffers) { ptr in
            UnsafeBufferPointer(start: ptr, count: n).reduce(0) { $0 + Int($1.mNumberChannels) } > 0
        }
    }

    private static func cfStringProperty(_ selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var cfRef: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &cfRef) == noErr,
              let str = cfRef?.takeRetainedValue() as String?, !str.isEmpty
        else { return nil }
        return str
    }

    private static func deviceUID(_ id: AudioDeviceID) -> String {
        cfStringProperty(kAudioDevicePropertyDeviceUID, for: id) ?? "unknown-\(id)"
    }

    private static func deviceName(_ id: AudioDeviceID) -> String {
        cfStringProperty(kAudioObjectPropertyName,      for: id) ??
        cfStringProperty(kAudioObjectPropertyModelName, for: id) ??
        cfStringProperty(kAudioDevicePropertyDeviceUID, for: id) ??
        "Device \(id)"
    }

    private static func scope(input: Bool) -> AudioObjectPropertyScope {
        input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
    }
}
