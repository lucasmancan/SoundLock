import AppKit
import SwiftUI

struct FooterView: View {
    @ObservedObject var monitor: AudioDeviceMonitor

    var body: some View {
        HStack {
            Spacer()
            footerButton(systemImage: "arrow.clockwise", help: "Refresh", color: .secondary) {
                monitor.refreshDevices()
            }
            Spacer()
            footerButton(systemImage: "speaker.wave.2", help: "Sound Settings", color: .secondary) {
                openSystemSettings(Constants.SystemURL.soundSettings)
            }
            Spacer()
            footerButton(systemImage: "dot.radiowaves.left.and.right", help: "Bluetooth Settings", color: .secondary) {
                openSystemSettings(Constants.SystemURL.bluetoothSettings)
            }
            Spacer()
            footerButton(systemImage: "power", help: "Quit SoundLock", color: .red) {
                NSApplication.shared.terminate(nil)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func footerButton(systemImage: String, help: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundColor(color)
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
