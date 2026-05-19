import CoreAudio
import Foundation

// ---------------------------------------------------------------------------
// CoreAudio C callbacks need a free function pointer, so we keep a weak
// module-private reference to the live monitor. CoreAudio fires these on its
// own thread; we always hop to main before touching observable state.
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

/// Orchestrator: owns device lists + priority lists, registers CoreAudio
/// listeners, asserts priority, and forwards volume/mute sync to the
/// dedicated services.
final class AudioDeviceMonitor: ObservableObject {

    // MARK: - Published state

    @Published var outputDevices: [AudioDevice] = []
    @Published var inputDevices: [AudioDevice] = []

    @Published var priorityOutputList: [PriorityDevice] = [] {
        didSet { repository.scheduleSaveOutputs(priorityOutputList) }
    }
    @Published var priorityInputList: [PriorityDevice] = [] {
        didSet { repository.scheduleSaveInputs(priorityInputList) }
    }

    @Published var guardEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(guardEnabled, forKey: Constants.DefaultsKey.guardEnabled)
            if guardEnabled {
                assertPriority(input: false)
                assertPriority(input: true)
            }
        }
    }

    // MARK: - Dependencies

    let volume: AudioVolumeService
    let mute: AudioMuteService
    private let repository: PriorityListRepository

    // MARK: - Property addresses (stored once)

    private var outputAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
    private var inputAddr  = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,  mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
    private var devicesAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,            mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)

    // BT-retry work items — cancelled on every new device-list event so rapid
    // connect/disconnect cycles don't pile up stale closures on the main queue.
    private var retryItems: [DispatchWorkItem] = []

    // MARK: - Computed

    var currentPriorityOutput: AudioDevice? {
        topConnected(list: priorityOutputList, in: outputDevices)
    }
    var currentPriorityInput: AudioDevice? {
        topConnected(list: priorityInputList, in: inputDevices)
    }

    // MARK: - Init

    init(volume: AudioVolumeService, mute: AudioMuteService, repository: PriorityListRepository) {
        self.volume = volume
        self.mute = mute
        self.repository = repository
        self.guardEnabled = UserDefaults.standard.object(forKey: Constants.DefaultsKey.guardEnabled) as? Bool ?? true
        self.priorityOutputList = repository.loadOutputs()
        self.priorityInputList = repository.loadInputs()
    }

    // MARK: - Monitoring lifecycle

    func startMonitoring() {
        _sharedMonitor = self
        refreshDevices()
        // Assert immediately so changes made while the app was closed or the
        // guard was off are corrected before the first UI frame.
        assertPriority(input: false)
        assertPriority(input: true)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListener(sys, &outputAddr,  _outputListener,  nil)
        AudioObjectAddPropertyListener(sys, &inputAddr,   _inputListener,   nil)
        AudioObjectAddPropertyListener(sys, &devicesAddr, _devicesListener, nil)
    }

    func stopMonitoring() {
        retryItems.forEach { $0.cancel() }
        retryItems.removeAll()
        repository.cancelPending()
        let sys = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectRemovePropertyListener(sys, &outputAddr,  _outputListener,  nil)
        AudioObjectRemovePropertyListener(sys, &inputAddr,   _inputListener,   nil)
        AudioObjectRemovePropertyListener(sys, &devicesAddr, _devicesListener, nil)
        _sharedMonitor = nil
    }

    // MARK: - Device refresh

    func refreshDevices() {
        let (out, inp) = CoreAudioBridge.enumeratePhysicalDevices()
        outputDevices = out
        inputDevices = inp
        batchUpdatePriorityNames()
        syncAudioState()
    }

    // MARK: - Priority list CRUD

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
        if input { priorityInputList.removeAll { $0.uid == uid } }
        else      { priorityOutputList.removeAll { $0.uid == uid } }
    }

    func movePriority(from: IndexSet, to: Int, input: Bool) {
        if input { priorityInputList.move(fromOffsets: from, toOffset: to) }
        else      { priorityOutputList.move(fromOffsets: from, toOffset: to) }
        assertPriority(input: input)
        syncAudioState()
    }

    // MARK: - Listener callbacks

    func handleDeviceChange(input: Bool) {
        assertPriority(input: input)
        syncAudioState()
    }

    func handleDeviceListChange() {
        retryItems.forEach { $0.cancel() }
        retryItems.removeAll()

        refreshDevices()
        assertPriority(input: false)
        assertPriority(input: true)

        // Cover macOS's delayed BT auto-switch (fires 1-3 s after pairing).
        // First retry re-enumerates so newly assigned IDs are picked up.
        for (index, delay) in Constants.Timing.btRecoveryDelays.enumerated() {
            let shouldRefresh = (index == 0)
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.guardEnabled else { return }
                if shouldRefresh { self.refreshDevices() }
                self.assertPriority(input: false)
                self.assertPriority(input: true)
            }
            retryItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    // MARK: - Private

    private func syncAudioState() {
        volume.syncFromDevices(output: currentPriorityOutput, input: currentPriorityInput)
        mute.syncFromDevices(output: currentPriorityOutput, input: currentPriorityInput)
    }

    private func assertPriority(input: Bool) {
        guard guardEnabled else { return }
        let list      = input ? priorityInputList : priorityOutputList
        let connected = input ? inputDevices       : outputDevices
        guard let bestEntry  = list.first(where: { e in connected.contains { $0.uid == e.uid } }),
              let bestDevice = connected.first(where: { $0.uid == bestEntry.uid })
        else { return }
        let current = CoreAudioBridge.getDefaultDevice(input: input)
        if current != bestDevice.id {
            let err = CoreAudioBridge.setDefaultDevice(bestDevice.id, input: input)
            if err != noErr {
                NSLog("[SoundLock] setDefault failed (input=%d, deviceID=%d): OSStatus %d", input, bestDevice.id, err)
            }
        }
    }

    /// Updates stored device names in-place, assigning each list at most once
    /// so didSet (and its debounced save) fires at most once per list.
    private func batchUpdatePriorityNames() {
        priorityOutputList = mergedNames(priorityOutputList, from: outputDevices) ?? priorityOutputList
        priorityInputList  = mergedNames(priorityInputList,  from: inputDevices)  ?? priorityInputList
    }

    private func mergedNames(_ list: [PriorityDevice], from devices: [AudioDevice]) -> [PriorityDevice]? {
        var copy = list
        var changed = false
        for i in copy.indices {
            if let live = devices.first(where: { $0.uid == copy[i].uid }),
               live.name != copy[i].name {
                copy[i].name = live.name
                changed = true
            }
        }
        return changed ? copy : nil
    }

    private func topConnected(list: [PriorityDevice], in devices: [AudioDevice]) -> AudioDevice? {
        let uids = Set(devices.map(\.uid))
        guard let best = list.first(where: { uids.contains($0.uid) }) else { return nil }
        return devices.first { $0.uid == best.uid }
    }
}
