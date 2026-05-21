import AppKit
import SwiftUI

enum Theme {
    static let rowHeight: CGFloat = 32
    static let horizontalInset: CGFloat = 16
    static let headerHorizontalInset: CGFloat = 20
    static let sectionVerticalPadding: CGFloat = 6
    static let sectionSpacing: CGFloat = 4
    static let rowIconSize: CGFloat = 14
    static let rowIconFrame: CGFloat = 22
    static let dividerOpacity: Double = 0.3

    static let sectionTitleFont: Font = .system(size: 11, weight: .semibold)
    static let rowTitleFont: Font = .system(size: 12)
    static let headerTitleFont: Font = .system(size: 13, weight: .semibold)
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}
