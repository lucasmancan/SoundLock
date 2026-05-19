import SwiftUI
import CoreAudio

struct ContentView: View {
    @EnvironmentObject var monitor:  AudioDeviceMonitor
    @EnvironmentObject var settings: AppSettings

    // Header subtitle — shows what's being protected or why nothing is happening
    var statusSubtitle: String {
        guard monitor.guardEnabled else { return "Off — audio routing unguarded" }
        let out = monitor.currentPriorityOutput?.name
        let inp = monitor.currentPriorityInput?.name
        switch (out, inp) {
        case (nil, nil): return "No priority devices set yet"
        case (let o?, nil): return "Protecting \(o)"
        case (nil, let i?): return "Protecting \(i)"
        case (let o?, _):   return "Protecting \(o)"
        }
    }
    var statusColor: Color {
        guard monitor.guardEnabled else { return .secondary }
        let hasPriority = monitor.currentPriorityOutput != nil || monitor.currentPriorityInput != nil
        return hasPriority ? .green : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ─────────────────────────────────────────────
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

            Divider()

            // ── Volume & mute ──────────────────────────────────────
            VStack(spacing: 6) {
                VolumeRow(
                    icon: monitor.outputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    iconColor: monitor.outputMuted ? .red : .blue,
                    deviceName: monitor.currentPriorityOutput?.name,
                    volume: Binding(get: { monitor.outputVolume }, set: { monitor.setOutputVolume($0) }),
                    volumeAvailable: monitor.outputVolumeAvailable,
                    muted: monitor.outputMuted,
                    isInput: false,
                    onMuteToggle: { monitor.toggleOutputMute() }
                )
                VolumeRow(
                    icon: monitor.inputMuted ? "mic.slash.fill" : "mic.fill",
                    iconColor: monitor.inputMuted ? .red : .blue,
                    deviceName: monitor.currentPriorityInput?.name,
                    volume: Binding(get: { monitor.inputVolume }, set: { monitor.setInputVolume($0) }),
                    volumeAvailable: monitor.inputVolumeAvailable,
                    muted: monitor.inputMuted,
                    isInput: true,
                    onMuteToggle: { monitor.toggleInputMute() }
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // ── Priority lists + settings ──────────────────────────
            VStack(alignment: .leading, spacing: 10) {

                    PriorityListSection(
                        title: "Output Priority",
                        systemImage: "speaker.wave.2.fill",
                        connectedDevices: monitor.outputDevices,
                        priorityList: $monitor.priorityOutputList,
                        onAdd:    { monitor.addToPriority($0, input: false) },
                        onRemove: { monitor.removeFromPriority(uid: $0, input: false) },
                        onMove:   { monitor.movePriority(from: $0, to: $1, input: false) }
                    )

                    Divider().padding(.horizontal, 12).padding(.vertical, 2)

                    PriorityListSection(
                        title: "Input Priority",
                        systemImage: "mic.fill",
                        connectedDevices: monitor.inputDevices,
                        priorityList: $monitor.priorityInputList,
                        onAdd:    { monitor.addToPriority($0, input: true) },
                        onRemove: { monitor.removeFromPriority(uid: $0, input: true) },
                        onMove:   { monitor.movePriority(from: $0, to: $1, input: true) }
                    )

                    Divider().padding(.horizontal, 12)

                    // ── Settings ───────────────────────────────────
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
                            get:  { settings.launchAtLoginEnabled },
                            set:  { settings.launchAtLoginEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.7)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            .padding(.vertical, 8)

            Divider()

            // ── Footer ─────────────────────────────────────────────
            HStack {
                Spacer()

                Button { monitor.refreshDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .cursor(.pointingHand)

                Spacer()

                Button {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Sound Settings")
                .cursor(.pointingHand)

                Spacer()

                Button {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
                } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Bluetooth Settings")
                .cursor(.pointingHand)

                Spacer()

                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Quit SoundLock")
                .cursor(.pointingHand)

                Spacer()
            }
            .padding(.vertical, 8)
        }
        .frame(minWidth: 300, maxWidth: 300)
    }
}

// ---------------------------------------------------------------------------
// Volume row
// ---------------------------------------------------------------------------
struct VolumeRow: View {
    let icon: String
    let iconColor: Color
    let deviceName: String?
    @Binding var volume: Double
    let volumeAvailable: Bool
    let muted: Bool
    let isInput: Bool
    let onMuteToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onMuteToggle) {
                Image(systemName: muted
                    ? (isInput ? "mic.slash.fill"  : "speaker.slash.fill")
                    : (isInput ? "mic.fill"        : "speaker.wave.2.fill"))
                    .foregroundColor(muted ? .red : .blue)
                    .font(.system(size: 16))
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .cursor(.pointingHand)

            VStack(alignment: .leading, spacing: 3) {
                if let name = deviceName {
                    Text(name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                } else {
                    Text("Add a device to the priority list below")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }

                if deviceName != nil {
                    if volumeAvailable {
                        HStack(spacing: 6) {
                            Slider(value: $volume, in: 0...1)
                                .controlSize(.small)
                                .disabled(muted)
                                .opacity(muted ? 0.35 : 1)
                            Text("\(Int(volume * 100))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 26, alignment: .trailing)
                        }
                    } else {
                        Text("Volume not adjustable")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Priority list section
// ---------------------------------------------------------------------------
struct PriorityListSection: View {
    let title: String
    let systemImage: String
    let connectedDevices: [AudioDevice]
    @Binding var priorityList: [PriorityDevice]
    let onAdd:    (AudioDevice) -> Void
    let onRemove: (String) -> Void
    let onMove:   (IndexSet, Int) -> Void

    var addableDevices: [AudioDevice] {
        let uids = Set(priorityList.map { $0.uid })
        return connectedDevices.filter { !uids.contains($0.uid) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)

            if priorityList.isEmpty && addableDevices.isEmpty {
                Text("No physical devices found")
                    .font(.caption2).foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            }

            // Ordered priority entries
            if !priorityList.isEmpty {
                List {
                    ForEach(Array(priorityList.enumerated()), id: \.element.id) { index, entry in
                        let connected = connectedDevices.contains { $0.uid == entry.uid }
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(connected ? Color.blue : Color.secondary.opacity(0.25))
                                    .frame(width: 17, height: 17)
                                Text("\(index + 1)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(entry.name)
                                    .font(.callout).lineLimit(1)
                                    .foregroundColor(connected ? .primary : .secondary)
                                if !connected {
                                    Text("Offline")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button { onRemove(entry.uid) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.borderless)
                            .cursor(.pointingHand)
                        }
                        .frame(height: 34)
                        .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                    }
                    .onMove { onMove($0, $1) }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 34)
                .frame(height: CGFloat(priorityList.count) * 34)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                .padding(.horizontal, 12)
            }

            // Addable connected devices
            if !addableDevices.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(addableDevices) { device in
                        Button { onAdd(device) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 11))
                                Text(device.name)
                                    .font(.callout).foregroundColor(.primary).lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .cursor(.pointingHand)
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Cursor helper
// ---------------------------------------------------------------------------
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in if inside { cursor.push() } else { NSCursor.pop() } }
    }
}
