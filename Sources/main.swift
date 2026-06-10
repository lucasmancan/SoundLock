import Cocoa

// Single-instance guard: if another copy is already running, hand it focus and exit.
// LaunchServices won't dedupe an unsigned bundle, so each launch spawns a duplicate
// unless we stop it here — before the delegate touches CoreAudio or the menu bar.
if let bundleID = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0 != NSRunningApplication.current }
    if let existing = others.first {
        existing.activate(options: [.activateAllWindows])
        NSLog("SoundLock already running (pid \(existing.processIdentifier)); exiting duplicate.")
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // No dock icon — lives only in the menu bar
app.run()
