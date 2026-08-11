import AppKit
import SwiftUI

extension View {
    /// Pushes the given cursor while hovering, pops it on exit.
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
