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
        topConnected(list: priorityOutputList, in: outputDevices, input: false)
    }
    var currentPriorityInput: AudioDevice? {
        topConnected(list: priorityInputList, in: inputDevices, input: true)
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
        reconcilePriorityLists()
        syncAudioState()
    }

    // MARK: - Priority list CRUD

    func addToPriority(_ device: AudioDevice, input: Bool) {
        if input {
            guard !AudioDeviceIdentityResolver.isRepresented(device, in: priorityInputList, input: true) else { return }
            priorityInputList.append(PriorityDevice(device: device, input: true))
        } else {
            guard !AudioDeviceIdentityResolver.isRepresented(device, in: priorityOutputList, input: false) else { return }
            priorityOutputList.append(PriorityDevice(device: device, input: false))
        }
        assertPriority(input: input)
        syncAudioState()
    }

    func removeFromPriority(stableKey: String, input: Bool) {
        if input { priorityInputList.removeAll { $0.identityKey(input: true) == stableKey } }
        else      { priorityOutputList.removeAll { $0.identityKey(input: false) == stableKey } }
    }

    func movePriority(from: IndexSet, to: Int, input: Bool) {
        if input { priorityInputList.move(fromOffsets: from, toOffset: to) }
        else      { priorityOutputList.move(fromOffsets: from, toOffset: to) }
        assertPriority(input: input)
        syncAudioState()
    }

    func isRepresentedInPriority(_ device: AudioDevice, input: Bool) -> Bool {
        AudioDeviceIdentityResolver.isRepresented(
            device,
            in: input ? priorityInputList : priorityOutputList,
            input: input
        )
    }

    func isPriorityDeviceConnected(_ entry: PriorityDevice, input: Bool) -> Bool {
        AudioDeviceIdentityResolver.matchDevice(
            for: entry,
            in: input ? inputDevices : outputDevices,
            input: input
        ) != nil
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
        guard let bestEntry = list.first(where: { AudioDeviceIdentityResolver.matchDevice(for: $0, in: connected, input: input) != nil }),
              let bestDevice = AudioDeviceIdentityResolver.matchDevice(for: bestEntry, in: connected, input: input)
        else { return }
        let current = CoreAudioBridge.getDefaultDevice(input: input)
        if current != bestDevice.id {
            let err = CoreAudioBridge.setDefaultDevice(bestDevice.id, input: input)
            if err != noErr {
                NSLog("[SoundLock] setDefault failed (input=%d, deviceID=%d): OSStatus %d", input, bestDevice.id, err)
            }
        }
    }

    private func reconcilePriorityLists() {
        let nextOutputs = AudioDeviceIdentityResolver.reconcile(priorityOutputList, with: outputDevices, input: false) { message in
            NSLog("%@", message)
        }
        if nextOutputs != priorityOutputList {
            priorityOutputList = nextOutputs
        }

        let nextInputs = AudioDeviceIdentityResolver.reconcile(priorityInputList, with: inputDevices, input: true) { message in
            NSLog("%@", message)
        }
        if nextInputs != priorityInputList {
            priorityInputList = nextInputs
        }
    }

    private func topConnected(list: [PriorityDevice], in devices: [AudioDevice], input: Bool) -> AudioDevice? {
        guard let best = list.first(where: { AudioDeviceIdentityResolver.matchDevice(for: $0, in: devices, input: input) != nil }) else { return nil }
        return AudioDeviceIdentityResolver.matchDevice(for: best, in: devices, input: input)
    }
}
