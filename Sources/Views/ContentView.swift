import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: AudioDeviceMonitor
    @EnvironmentObject var volume: AudioVolumeService
    @EnvironmentObject var mute: AudioMuteService
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(monitor: monitor)
            Divider()

            VStack(spacing: 6) {
                VolumeControlView(
                    direction: .output,
                    volume: volume,
                    mute: mute,
                    deviceName: monitor.currentPriorityOutput?.name
                )
                VolumeControlView(
                    direction: .input,
                    volume: volume,
                    mute: mute,
                    deviceName: monitor.currentPriorityInput?.name
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                PriorityListSectionView(
                    title: "Output Priority",
                    systemImage: "speaker.wave.2.fill",
                    direction: .output,
                    monitor: monitor
                )

                Divider().padding(.horizontal, 12).padding(.vertical, 2)

                PriorityListSectionView(
                    title: "Input Priority",
                    systemImage: "mic.fill",
                    direction: .input,
                    monitor: monitor
                )

                Divider().padding(.horizontal, 12)

                launchAtLoginRow
            }
            .padding(.vertical, 8)

            Divider()

            FooterView(monitor: monitor)
        }
        .frame(minWidth: Constants.UI.popoverWidth, maxWidth: Constants.UI.popoverWidth)
    }

    private var launchAtLoginRow: some View {
        HStack {
            Image(systemName: "arrow.up.circle")
                .frame(width: 14)
                .foregroundColor(.secondary)
                .font(.caption)
            Text("Launch at login")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { settings.launchAtLoginEnabled },
                set: { settings.launchAtLoginEnabled = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .scaleEffect(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}
