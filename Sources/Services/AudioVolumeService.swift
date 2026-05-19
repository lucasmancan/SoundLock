import CoreAudio
import Foundation

/// Per-direction volume state for the current priority device.
/// Views bind directly to `@Published` properties; the monitor calls
/// `syncFromDevices(...)` whenever the priority device changes.
final class AudioVolumeService: ObservableObject {

    @Published var outputVolume: Double = 1.0
    @Published var inputVolume: Double = 1.0
    @Published var outputAvailable: Bool = false
    @Published var inputAvailable: Bool = false

    private var currentOutputID: AudioDeviceID?
    private var currentInputID: AudioDeviceID?

    func setOutputVolume(_ vol: Double) {
        guard let id = currentOutputID else { return }
        outputVolume = vol
        CoreAudioBridge.setVolume(Float(vol), deviceID: id, input: false)
    }

    func setInputVolume(_ vol: Double) {
        guard let id = currentInputID else { return }
        inputVolume = vol
        CoreAudioBridge.setVolume(Float(vol), deviceID: id, input: true)
    }

    /// Refresh state from the given priority devices. Passing `nil` clears availability.
    func syncFromDevices(output: AudioDevice?, input: AudioDevice?) {
        currentOutputID = output?.id
        currentInputID = input?.id

        if let id = currentOutputID {
            outputAvailable = CoreAudioBridge.canControlVolume(id, input: false)
            if outputAvailable { outputVolume = Double(CoreAudioBridge.getVolume(id, input: false)) }
        } else {
            outputAvailable = false
        }

        if let id = currentInputID {
            inputAvailable = CoreAudioBridge.canControlVolume(id, input: true)
            if inputAvailable { inputVolume = Double(CoreAudioBridge.getVolume(id, input: true)) }
        } else {
            inputAvailable = false
        }
    }
}
