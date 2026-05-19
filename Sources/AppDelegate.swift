import Cocoa
import SwiftUI
import ServiceManagement

// ---------------------------------------------------------------------------
// AppSettings — holds app-level preferences
// ---------------------------------------------------------------------------
class AppSettings: ObservableObject {
    var launchAtLoginEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register()   }
                else        { try SMAppService.mainApp.unregister() }
            } catch {
                // Surface authorization errors rather than swallowing them.
                // The toggle will appear on but the system rejected it — log clearly.
                NSLog("[SoundLock] SMAppService error (%@): %@",
                      newValue ? "register" : "unregister", error.localizedDescription)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// AppDelegate
// ---------------------------------------------------------------------------
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var hostingController: NSHostingController<AnyView>?
    let monitor  = AudioDeviceMonitor()
    let settings = AppSettings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Always menu-bar only, no Dock icon
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

        let contentView = AnyView(ContentView()
            .environmentObject(monitor)
            .environmentObject(settings))
        let hc = NSHostingController(rootView: contentView)
        hostingController = hc
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.contentViewController = hc

        monitor.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stopMonitoring()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.badge.plus",
                                   accessibilityDescription: "SoundLock")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let popover {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                // Size to content, capped at available screen height
                let screen = button.window?.screen ?? NSScreen.main
                let maxHeight = (screen?.visibleFrame.height ?? 800) - 16
                let ideal = hostingController?.sizeThatFits(in: NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
                let height = min(ideal?.height ?? 500, maxHeight)
                popover.contentSize = NSSize(width: 300, height: height)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
