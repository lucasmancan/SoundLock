import CoreAudio
import Foundation

// ---------------------------------------------------------------------------
// Global weak reference for C-compatible listener callbacks.
// CoreAudio fires these on its own internal thread; we always hop to main.
// ---------------------------------------------------------------------------
private weak var _sharedMonitor: AudioDeviceMonitor?

private let _outputListener: AudioObjectPropertyListenerProc = { _, _, _, _ in
    DispatchQueue.main.async { _sharedMonitor?.handleDeviceChange(input: false) }
    return noErr
}
private let _inputListener: AudioObjectPropertyListenerProc = { _, _, _, _ in
    DispatchQueue.main.async { _sharedMonitor?.handleDeviceChange(input: true) }
    return noErr
}
private let _devicesListener: AudioObjectPropertyListenerProc = { _, _, _, _ in
    DispatchQueue.main.async { _sharedMonitor?.handleDeviceListChange() }
    return noErr
}

// Physical transport types — everything else (virtual, aggregate, unknown) is excluded
private let physicalTransportTypes: Set<UInt32> = [
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

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID   // ephemeral — changes on every reconnect
    let uid: String         // stable (kAudioDevicePropertyDeviceUID)
    let name: String
}

struct PriorityDevice: Identifiable, Codable, Equatable {
    let uid: String
    var name: String
    var id: String { uid }
}

// ---------------------------------------------------------------------------
// AudioDeviceMonitor
// ---------------------------------------------------------------------------
class AudioDeviceMonitor: ObservableObject {

    // Connected devices (physical only)
    @Published var outputDevices: [AudioDevice] = []
    @Published var inputDevices:  [AudioDevice] = []

    // Ordered priority lists (persisted); saves are debounced to avoid
    // redundant UserDefaults writes on rapid mutations (e.g. drag-reorder).
    @Published var priorityOutputList: [PriorityDevice] = [] {
        didSet { scheduleOutputSave() }
    }
    @Published var priorityInputList: [PriorityDevice] = [] {
        didSet { scheduleInputSave() }
    }

    @Published var guardEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(guardEnabled, forKey: "guardEnabled")
            if guardEnabled {
                assertPriority(input: false)
                assertPriority(input: true)
            }
        }
    }

    // Volume (0.0 – 1.0) for the current priority device in each direction
    @Published var outputVolume: Double = 1.0
    @Published var inputVolume:  Double = 1.0
    @Published var outputVolumeAvailable: Bool = false
    @Published var inputVolumeAvailable:  Bool = false

    // Mute state
    @Published var outputMuted: Bool = false
    @Published var inputMuted:  Bool = false

    // Current top-priority connected device
    var currentPriorityOutput: AudioDevice? {
        let uids = Set(outputDevices.map { $0.uid })
        guard let best = priorityOutputList.first(where: { uids.contains($0.uid) }) else { return nil }
        return outputDevices.first { $0.uid == best.uid }
    }
    var currentPriorityInput: AudioDevice? {
        let uids = Set(inputDevices.map { $0.uid })
        guard let best = priorityInputList.first(where: { uids.contains($0.uid) }) else { return nil }
        return inputDevices.first { $0.uid == best.uid }
    }

    // CoreAudio property addresses — stored once to avoid repeated stack allocation
    private var outputAddr  = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
    private var inputAddr   = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,  mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
    private var devicesAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,             mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)

    // Pending BT-retry work items — cancelled & replaced on every new device-list event
    // so rapid connect/disconnect cycles don't accumulate stale closures on the main queue.
    private var retryItems: [DispatchWorkItem] = []

    // Debounced save work items — one per list, cancelled & rescheduled on each mutation.
    private var saveOutputWork: DispatchWorkItem?
    private var saveInputWork:  DispatchWorkItem?

    // Shared codec instances — allocated once for the lifetime of the monitor.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // ------------------------------------------------------------------
    init() {
        guardEnabled       = UserDefaults.standard.object(forKey: "guardEnabled") as? Bool ?? true
        priorityOutputList = loadPriorityList(key: "priorityOutputList")
        priorityInputList  = loadPriorityList(key: "priorityInputList")
    }

    // ------------------------------------------------------------------
    // MARK: - Monitoring lifecycle
    // ------------------------------------------------------------------

    func startMonitoring() {
        _sharedMonitor = self
        refreshDevices()
        // Assert immediately so any changes made while the app was closed
        // or the guard was off are corrected before the first UI frame.
        assertPriority(input: false)
        assertPriority(input: true)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListener(sys, &outputAddr,  _outputListener,  nil)
        AudioObjectAddPropertyListener(sys, &inputAddr,   _inputListener,   nil)
        AudioObjectAddPropertyListener(sys, &devicesAddr, _devicesListener, nil)
    }

    func stopMonitoring() {
        // Cancel all pending work so nothing fires after the monitor is torn down.
        retryItems.forEach { $0.cancel() }
        retryItems.removeAll()
        saveOutputWork?.cancel()
        saveInputWork?.cancel()
        let sys = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectRemovePropertyListener(sys, &outputAddr,  _outputListener,  nil)
        AudioObjectRemovePropertyListener(sys, &inputAddr,   _inputListener,   nil)
        AudioObjectRemovePropertyListener(sys, &devicesAddr, _devicesListener, nil)
        _sharedMonitor = nil
    }

    func refreshDevices() {
        // Single CoreAudio enumeration pass — builds both output and input lists at once
        // instead of fetching the device array from the kernel twice.
        let (out, inp) = enumeratePhysicalDevices()
        outputDevices = out
        inputDevices  = inp
        batchUpdatePriorityNames()
        syncAudioState()
    }

    // ------------------------------------------------------------------
    // MARK: - Priority list management
    // ------------------------------------------------------------------

    func addToPriority(_ device: AudioDevice, input: Bool) {
        if input {
            guard !priorityInputList.contains(where: { $0.uid == device.uid }) else { return }
            priorityInputList.append(PriorityDevice(uid: device.uid, name: device.name))
        } else {
            guard !priorityOutputList.contains(where: { $0.uid == device.uid }) else { return }
            priorityOutputList.append(PriorityDevice(uid: device.uid, name: device.name))
        }
        assertPriority(input: input)
        syncAudioState()
    }

    func removeFromPriority(uid: String, input: Bool) {
        if input { priorityInputList.removeAll  { $0.uid == uid } }
        else      { priorityOutputList.removeAll { $0.uid == uid } }
    }

    func movePriority(from: IndexSet, to: Int, input: Bool) {
        if input { priorityInputList.move(fromOffsets: from, toOffset: to) }
        else      { priorityOutputList.move(fromOffsets: from, toOffset: to) }
        assertPriority(input: input)
        syncAudioState()
    }

    // ------------------------------------------------------------------
    // MARK: - Listener callbacks
    // ------------------------------------------------------------------

    func handleDeviceChange(input: Bool) {
        assertPriority(input: input)
        syncAudioState()
    }

    func handleDeviceListChange() {
        // Cancel stale retries from a previous event before scheduling new ones.
        // Without this, rapid BT connect/disconnect cycles pile up closures on
        // the main queue (3 closures × N events) — all of which were already
        // superseded by the latest device state.
        retryItems.forEach { $0.cancel() }
        retryItems.removeAll()

        refreshDevices()
        assertPriority(input: false)
        assertPriority(input: true)

        // Schedule a small number of retries to cover macOS's delayed BT
        // auto-switch (typically fires 1-3 s after pairing completes).
        let schedule: [(delay: Double, refresh: Bool)] = [
            (0.5, true),   // re-enumerate so newly assigned IDs are picked up
            (1.5, false),
            (3.5, false),
        ]
        for (delay, refresh) in schedule {
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.guardEnabled else { return }
                if refresh { self.refreshDevices() }
                self.assertPriority(input: false)
                self.assertPriority(input: true)
            }
            retryItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    // ------------------------------------------------------------------
    // MARK: - Volume
    // ------------------------------------------------------------------

    func setOutputVolume(_ vol: Double) {
        guard let device = currentPriorityOutput else { return }
        outputVolume = vol
        setVolume(Float(vol), deviceID: device.id, input: false)
    }

    func setInputVolume(_ vol: Double) {
        guard let device = currentPriorityInput else { return }
        inputVolume = vol
        setVolume(Float(vol), deviceID: device.id, input: true)
    }

    private func setVolume(_ volume: Float, deviceID: AudioDeviceID, input: Bool) {
        let scope: AudioObjectPropertyScope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
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

    private func getVolume(_ deviceID: AudioDeviceID, input: Bool) -> Float {
        let scope: AudioObjectPropertyScope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        for element: AudioObjectPropertyElement in [0, 1] {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            var vol: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol) == noErr { return vol }
        }
        return 1.0
    }

    private func canControlVolume(_ deviceID: AudioDeviceID, input: Bool) -> Bool {
        let scope: AudioObjectPropertyScope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        for element: AudioObjectPropertyElement in [0, 1] {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
            var isSettable: DarwinBoolean = false
            if AudioObjectIsPropertySettable(deviceID, &addr, &isSettable) == noErr, isSettable.boolValue { return true }
        }
        return false
    }

    // ------------------------------------------------------------------
    // MARK: - Mute
    // ------------------------------------------------------------------

    func toggleOutputMute() {
        guard let device = currentPriorityOutput else { return }
        let newMuted = !outputMuted
        setMute(newMuted, deviceID: device.id, input: false)
        outputMuted = newMuted
    }

    func toggleInputMute() {
        guard let device = currentPriorityInput else { return }
        let newMuted = !inputMuted
        setMute(newMuted, deviceID: device.id, input: true)
        inputMuted = newMuted
    }

    private func setMute(_ muted: Bool, deviceID: AudioDeviceID, input: Bool) {
        var value: UInt32 = muted ? 1 : 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
            mElement: 0)
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func getMute(_ deviceID: AudioDeviceID, input: Bool) -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
            mElement: 0)
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value)
        return value == 1
    }

    // Sync volume + mute from the current priority devices
    private func syncAudioState() {
        if let d = currentPriorityOutput {
            outputVolumeAvailable = canControlVolume(d.id, input: false)
            if outputVolumeAvailable { outputVolume = Double(getVolume(d.id, input: false)) }
            outputMuted = getMute(d.id, input: false)
        } else {
            outputVolumeAvailable = false
        }
        if let d = currentPriorityInput {
            inputVolumeAvailable = canControlVolume(d.id, input: true)
            if inputVolumeAvailable { inputVolume = Double(getVolume(d.id, input: true)) }
            inputMuted = getMute(d.id, input: true)
        } else {
            inputVolumeAvailable = false
        }
    }

    // ------------------------------------------------------------------
    // MARK: - Priority assertion
    // ------------------------------------------------------------------

    private func assertPriority(input: Bool) {
        guard guardEnabled else { return }
        let list      = input ? priorityInputList  : priorityOutputList
        let connected = input ? inputDevices        : outputDevices
        guard let bestEntry  = list.first(where: { e in connected.contains { $0.uid == e.uid } }),
              let bestDevice = connected.first(where: { $0.uid == bestEntry.uid })
        else { return }
        let current = getDefault(input: input)
        if current != bestDevice.id { setDefault(bestDevice.id, input: input) }
    }

    /// Updates stored device names in-place, assigning each list at most once so
    /// didSet (and its debounced save) fires at most once per list per refresh.
    private func batchUpdatePriorityNames() {
        var outList = priorityOutputList
        var outChanged = false
        for i in outList.indices {
            if let live = outputDevices.first(where: { $0.uid == outList[i].uid }),
               live.name != outList[i].name {
                outList[i].name = live.name
                outChanged = true
            }
        }
        if outChanged { priorityOutputList = outList }

        var inList = priorityInputList
        var inChanged = false
        for i in inList.indices {
            if let live = inputDevices.first(where: { $0.uid == inList[i].uid }),
               live.name != inList[i].name {
                inList[i].name = live.name
                inChanged = true
            }
        }
        if inChanged { priorityInputList = inList }
    }

    private func getDefault(input: Bool) -> AudioDeviceID {
        var deviceID: AudioDeviceID = kAudioDeviceUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func setDefault(_ deviceID: AudioDeviceID, input: Bool) {
        var id = deviceID
        var addr = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        let err = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                             UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        if err != noErr {
            NSLog("[SoundLock] setDefault failed (input=%d, deviceID=%d): OSStatus %d", input, deviceID, err)
        }
    }

    // ------------------------------------------------------------------
    // MARK: - Device enumeration  (single pass — physical devices only)
    // ------------------------------------------------------------------

    /// Fetches the device list from CoreAudio exactly once and builds both the
    /// output and input arrays in a single iteration. Previously this was done
    /// in two separate calls, doubling the kernel round-trips.
    private func enumeratePhysicalDevices() -> (output: [AudioDevice], input: [AudioDevice]) {
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
            // Read UID and name once per device rather than once per direction.
            let uid  = deviceUID(id)
            let name = deviceName(id)
            if hasChannels(id, input: false) { outputs.append(AudioDevice(id: id, uid: uid, name: name)) }
            if hasChannels(id, input: true)  { inputs.append(AudioDevice(id: id, uid: uid, name: name)) }
        }
        return (outputs, inputs)
    }

    private func isPhysicalDevice(_ deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transport) == noErr
        else { return false }
        return physicalTransportTypes.contains(transport)
    }

    private func hasChannels(_ deviceID: AudioDeviceID, input: Bool) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
            mElement: 0)
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

    // ------------------------------------------------------------------
    // MARK: - Property helpers
    // ------------------------------------------------------------------

    private func cfStringProperty(_ selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var cfRef: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &cfRef) == noErr,
              let str = cfRef?.takeRetainedValue() as String?, !str.isEmpty
        else { return nil }
        return str
    }

    private func deviceUID(_ id: AudioDeviceID) -> String {
        cfStringProperty(kAudioDevicePropertyDeviceUID, for: id) ?? "unknown-\(id)"
    }
    private func deviceName(_ id: AudioDeviceID) -> String {
        cfStringProperty(kAudioObjectPropertyName,      for: id) ??
        cfStringProperty(kAudioObjectPropertyModelName, for: id) ??
        cfStringProperty(kAudioDevicePropertyDeviceUID, for: id) ??
        "Device \(id)"
    }

    // ------------------------------------------------------------------
    // MARK: - Persistence  (debounced writes, shared codec instances)
    // ------------------------------------------------------------------

    /// Debounced save for the output list. Cancels any pending write and reschedules
    /// 300 ms out, so a rapid sequence of mutations (drag-reorder) produces one write.
    private func scheduleOutputSave() {
        saveOutputWork?.cancel()
        let list = priorityOutputList
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let data = try self.encoder.encode(list)
                UserDefaults.standard.set(data, forKey: "priorityOutputList")
            } catch {
                NSLog("[SoundLock] Failed to save output priority list: %@", error.localizedDescription)
            }
        }
        saveOutputWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func scheduleInputSave() {
        saveInputWork?.cancel()
        let list = priorityInputList
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let data = try self.encoder.encode(list)
                UserDefaults.standard.set(data, forKey: "priorityInputList")
            } catch {
                NSLog("[SoundLock] Failed to save input priority list: %@", error.localizedDescription)
            }
        }
        saveInputWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func loadPriorityList(key: String) -> [PriorityDevice] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? decoder.decode([PriorityDevice].self, from: data)
        else { return [] }
        return list
    }
}
