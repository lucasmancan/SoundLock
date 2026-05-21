import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: AudioDeviceMonitor
    @EnvironmentObject var volume: AudioVolumeService
    @EnvironmentObject var mute: AudioMuteService
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(monitor: monitor)
            sectionDivider

            VStack(spacing: 4) {
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
            .padding(.vertical, Theme.sectionVerticalPadding)
            sectionDivider

            PriorityListSectionView(
                title: "Output Priority",
                systemImage: "speaker.wave.2.fill",
                direction: .output,
                monitor: monitor
            )
            .padding(.vertical, Theme.sectionVerticalPadding)
            sectionDivider

            PriorityListSectionView(
                title: "Input Priority",
                systemImage: "mic.fill",
                direction: .input,
                monitor: monitor
            )
            .padding(.vertical, Theme.sectionVerticalPadding)
            sectionDivider

            settingsSection
            sectionDivider

            FooterView(monitor: monitor)
                .padding(.vertical, 2)
        }
        .frame(minWidth: Constants.UI.popoverWidth, maxWidth: Constants.UI.popoverWidth)
        .background(VisualEffectBackground())
    }

    private var sectionDivider: some View {
        Divider().opacity(Theme.dividerOpacity)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            Text("Settings")
                .font(Theme.sectionTitleFont)
                .foregroundColor(.secondary)
                .padding(.horizontal, Theme.horizontalInset)
                .padding(.top, 2)

            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.circle")
                    .font(.system(size: Theme.rowIconSize))
                    .foregroundColor(.secondary)
                    .frame(width: Theme.rowIconFrame)
                Text("Launch at login")
                    .font(Theme.rowTitleFont)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.launchAtLoginEnabled },
                    set: { settings.launchAtLoginEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
            .padding(.horizontal, Theme.horizontalInset)
            .frame(height: Theme.rowHeight)
        }
        .padding(.vertical, Theme.sectionVerticalPadding)
    }
}
