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
        connectedDevices.filter { !monitor.isRepresentedInPriority($0, input: direction == .input) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            HStack(spacing: 6) {
                Text(title)
                    .font(Theme.sectionTitleFont)
                    .foregroundColor(.secondary)
                if priorityList.count >= 2 {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("drag to reorder")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, Theme.horizontalInset)
            .padding(.top, 2)

            if priorityList.isEmpty && addableDevices.isEmpty {
                Text("No physical devices found")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Theme.horizontalInset)
                    .padding(.vertical, 4)
            }

            if !priorityList.isEmpty { priorityListView }
            if !addableDevices.isEmpty { addableDevicesView }
        }
    }

    private var priorityListView: some View {
        List {
            ForEach(Array(priorityList.enumerated()), id: \.element.id) { index, entry in
                priorityRow(index: index, entry: entry)
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.horizontalInset,
                                              bottom: 0, trailing: Theme.horizontalInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onMove { from, to in monitor.movePriority(from: from, to: to, input: direction == .input) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, Theme.rowHeight)
        .frame(height: CGFloat(priorityList.count) * Theme.rowHeight)
    }

    private func priorityRow(index: Int, entry: PriorityDevice) -> some View {
        PriorityRow(
            index: index,
            entry: entry,
            connected: monitor.isPriorityDeviceConnected(entry, input: direction == .input),
            canDrag: priorityList.count >= 2,
            onRemove: { monitor.removeFromPriority(stableKey: entry.identityKey(input: direction == .input), input: direction == .input) }
        )
    }

    private struct PriorityRow: View {
        let index: Int
        let entry: PriorityDevice
        let connected: Bool
        let canDrag: Bool
        let onRemove: () -> Void
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 6) {
                if canDrag {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary.opacity(hovering ? 0.9 : 0.35))
                        .frame(width: 10)
                        .cursor(.openHand)
                }

                ZStack {
                    Circle()
                        .fill(connected ? Color.blue : Color.secondary.opacity(0.25))
                        .frame(width: Constants.UI.rankBadgeSize, height: Constants.UI.rankBadgeSize)
                    Text("\(index + 1)")
                        .font(.system(size: Constants.UI.rankBadgeFont, weight: .bold))
                        .foregroundColor(.white)
                }

                Text(entry.name)
                    .font(Theme.rowTitleFont)
                    .foregroundColor(connected ? .primary : .secondary)
                    .lineLimit(1)

                if !connected {
                    Text("Offline")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(hovering ? 0.9 : 0.5))
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .cursor(.pointingHand)
            }
            .padding(.horizontal, 4)
            .frame(height: Theme.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(hovering ? 0.12 : 0))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
    }

    private var addableDevicesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(addableDevices) { device in
                Button {
                    monitor.addToPriority(device, input: direction == .input)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: Theme.rowIconSize))
                            .frame(width: Theme.rowIconFrame)
                        Text(device.name)
                            .font(Theme.rowTitleFont)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.horizontalInset)
                    .frame(height: Theme.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .cursor(.pointingHand)
            }
        }
    }
}
