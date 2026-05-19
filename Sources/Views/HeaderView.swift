import SwiftUI

struct HeaderView: View {
    @ObservedObject var monitor: AudioDeviceMonitor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.circle.fill")
                .font(.title3)
                .foregroundColor(.blue)
            Text("SoundLock")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Toggle("", isOn: $monitor.guardEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
