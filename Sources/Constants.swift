import CoreGraphics
import Foundation

enum Constants {
    enum Timing {
        static let saveDebounce: TimeInterval = 0.3
        static let btRecoveryDelays: [TimeInterval] = [0.5, 1.5, 3.5]
    }

    enum UI {
        static let rowHeight: CGFloat = 34
        static let rankBadgeSize: CGFloat = 17
        static let rankBadgeFont: CGFloat = 9
        static let cornerRadius: CGFloat = 6
        static let strokeOpacity: Double = 0.12
        static let volumeIconSize: CGFloat = 16
        static let percentLabelWidth: CGFloat = 26
        static let placeholderOpacity: Double = 0.35
        static let popoverWidth: CGFloat = 300
        static let popoverEdgeInset: CGFloat = 16
        static let popoverDefaultHeight: CGFloat = 500
    }

    enum DefaultsKey {
        static let guardEnabled = "guardEnabled"
        static let priorityOutputList = "priorityOutputList"
        static let priorityInputList = "priorityInputList"
    }

    enum SystemURL {
        static let soundSettings = "x-apple.systempreferences:com.apple.Sound-Settings.extension"
        static let bluetoothSettings = "x-apple.systempreferences:com.apple.BluetoothSettings"
    }
}
