import SwiftUI

enum AudioDirection { case output, input }

struct VolumeControlView: View {
    let direction: AudioDirection
    @ObservedObject var volume: AudioVolumeService
    @ObservedObject var mute: AudioMuteService
    let deviceName: String?

    private var isInput: Bool { direction == .input }
    private var muted: Bool { isInput ? mute.inputMuted : mute.outputMuted }
    private var available: Bool { isInput ? volume.inputAvailable : volume.outputAvailable }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { isInput ? volume.inputVolume : volume.outputVolume },
            set: { isInput ? volume.setInputVolume($0) : volume.setOutputVolume($0) }
        )
    }

    private var iconName: String {
        switch (isInput, muted) {
        case (true, true):   return "mic.slash.fill"
        case (true, false):  return "mic.fill"
        case (false, true):  return "speaker.slash.fill"
        case (false, false): return "speaker.wave.2.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleMute) {
                Image(systemName: iconName)
                    .foregroundColor(muted ? .red : .blue)
                    .font(.system(size: Constants.UI.volumeIconSize))
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .cursor(.pointingHand)

            VStack(alignment: .leading, spacing: 3) {
                if let name = deviceName {
                    Text(name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    sliderOrPlaceholder
                } else {
                    Text("Add a device to the priority list below")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }

    @ViewBuilder
    private var sliderOrPlaceholder: some View {
        if available {
            HStack(spacing: 6) {
                Slider(value: volumeBinding, in: 0...1)
                    .controlSize(.small)
                    .disabled(muted)
                    .opacity(muted ? Constants.UI.placeholderOpacity : 1)
                Text("\(Int(volumeBinding.wrappedValue * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: Constants.UI.percentLabelWidth, alignment: .trailing)
            }
        } else {
            Text("Volume not adjustable")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func toggleMute() {
        if isInput { mute.toggleInputMute() } else { mute.toggleOutputMute() }
    }
}
