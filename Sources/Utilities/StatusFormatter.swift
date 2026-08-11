import SwiftUI

enum StatusFormatter {
    static func subtitle(monitor: AudioDeviceMonitor) -> String {
        guard monitor.guardEnabled else { return "Off — audio routing unguarded" }
        let out = monitor.currentPriorityOutput?.name
        let inp = monitor.currentPriorityInput?.name
        switch (out, inp) {
        case (nil, nil):    return "No priority devices set yet"
        case (let o?, _):   return "Protecting \(o)"
        case (nil, let i?): return "Protecting \(i)"
        }
    }

    static func color(monitor: AudioDeviceMonitor) -> Color {
        guard monitor.guardEnabled else { return .secondary }
        let hasPriority = monitor.currentPriorityOutput != nil || monitor.currentPriorityInput != nil
        return hasPriority ? .green : .orange
    }
}
