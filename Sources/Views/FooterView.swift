import AppKit
import SwiftUI

struct FooterView: View {
    @ObservedObject var monitor: AudioDeviceMonitor

    var body: some View {
        HStack(spacing: 0) {
            iconButton(systemImage: "arrow.clockwise", help: "Refresh Devices", color: .secondary) {
                monitor.refreshDevices()
            }
            iconButton(systemImage: "speaker.wave.2", help: "Sound Settings", color: .secondary) {
                openSystemSettings(Constants.SystemURL.soundSettings)
            }
            iconButton(systemImage: "dot.radiowaves.left.and.right", help: "Bluetooth Settings", color: .secondary) {
                openSystemSettings(Constants.SystemURL.bluetoothSettings)
            }
            iconButton(systemImage: "power", help: "Quit SoundLock", color: .red) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, Theme.horizontalInset)
        .padding(.vertical, 8)
    }

    private func iconButton(systemImage: String,
                            help: String,
                            color: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Theme.rowIconSize))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
        .cursor(.pointingHand)
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
