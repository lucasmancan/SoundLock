import SwiftUI

struct HeaderView: View {
    @ObservedObject var monitor: AudioDeviceMonitor

    var body: some View {
        HStack {
            Text("SoundLock")
                .font(Theme.headerTitleFont)
            Spacer()
            Toggle("", isOn: $monitor.guardEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, Theme.headerHorizontalInset)
        .padding(.vertical, 10)
    }
}
