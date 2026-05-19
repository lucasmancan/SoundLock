import CoreAudio
import Foundation

/// Per-direction mute state for the current priority device.
final class AudioMuteService: ObservableObject {

    @Published var outputMuted: Bool = false
    @Published var inputMuted: Bool = false

    private var currentOutputID: AudioDeviceID?
    private var currentInputID: AudioDeviceID?

    func toggleOutputMute() {
        guard let id = currentOutputID else { return }
        let next = !outputMuted
        CoreAudioBridge.setMute(next, deviceID: id, input: false)
        outputMuted = next
    }

    func toggleInputMute() {
        guard let id = currentInputID else { return }
        let next = !inputMuted
        CoreAudioBridge.setMute(next, deviceID: id, input: true)
        inputMuted = next
    }

    func syncFromDevices(output: AudioDevice?, input: AudioDevice?) {
        currentOutputID = output?.id
        currentInputID = input?.id
        outputMuted = output.map { CoreAudioBridge.getMute($0.id, input: false) } ?? false
        inputMuted = input.map { CoreAudioBridge.getMute($0.id, input: true) } ?? false
    }
}
