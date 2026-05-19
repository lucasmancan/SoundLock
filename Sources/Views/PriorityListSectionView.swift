import SwiftUI

struct PriorityListSectionView: View {
    let title: String
    let systemImage: String
    let direction: AudioDirection
    @ObservedObject var monitor: AudioDeviceMonitor

    private var connectedDevices: [AudioDevice] {
        direction == .input ? monitor.inputDevices : monitor.outputDevices
    }

    private var priorityList: [PriorityDevice] {
        direction == .input ? monitor.priorityInputList : monitor.priorityOutputList
    }

    private var addableDevices: [AudioDevice] {
        let uids = Set(priorityList.map(\.uid))
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

            if !priorityList.isEmpty { priorityListView }
            if !addableDevices.isEmpty { addableDevicesView }
        }
    }

    private var priorityListView: some View {
        List {
            ForEach(Array(priorityList.enumerated()), id: \.element.id) { index, entry in
                priorityRow(index: index, entry: entry)
                    .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
            }
            .onMove { from, to in monitor.movePriority(from: from, to: to, input: direction == .input) }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, Constants.UI.rowHeight)
        .frame(height: CGFloat(priorityList.count) * Constants.UI.rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: Constants.UI.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                .stroke(Color.secondary.opacity(Constants.UI.strokeOpacity), lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }

    private func priorityRow(index: Int, entry: PriorityDevice) -> some View {
        let connected = connectedDevices.contains { $0.uid == entry.uid }
        return HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(connected ? Color.blue : Color.secondary.opacity(0.25))
                    .frame(width: Constants.UI.rankBadgeSize, height: Constants.UI.rankBadgeSize)
                Text("\(index + 1)")
                    .font(.system(size: Constants.UI.rankBadgeFont, weight: .bold))
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
            Button {
                monitor.removeFromPriority(uid: entry.uid, input: direction == .input)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .cursor(.pointingHand)
        }
        .frame(height: Constants.UI.rowHeight)
    }

    private var addableDevicesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(addableDevices) { device in
                Button {
                    monitor.addToPriority(device, input: direction == .input)
                } label: {
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
