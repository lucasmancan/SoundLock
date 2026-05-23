import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var hostingController: NSHostingController<AnyView>?

    private let repository = PriorityListRepository()
    private let volume = AudioVolumeService()
    private let mute = AudioMuteService()
    let settings = AppSettings()
    lazy var monitor = AudioDeviceMonitor(volume: volume, mute: mute, repository: repository)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        setupStatusItem()

        let contentView = AnyView(
            ContentView()
                .environmentObject(monitor)
                .environmentObject(volume)
                .environmentObject(mute)
                .environmentObject(settings)
        )
        let hc = NSHostingController(rootView: contentView)
        hostingController = hc
        popover = NSPopover()
        popover?.behavior = .transient
        popover?.contentViewController = hc

        monitor.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        closePopover(notification)
        monitor.stopMonitoring()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = statusBarImage()
            button.imageScaling = .scaleProportionallyUpOrDown
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    private func statusBarImage() -> NSImage? {
        if let path = Bundle.main.path(forResource: "StatusIcon", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            image.isTemplate = true
            image.size = NSSize(width: 24, height: 24)
            image.accessibilityDescription = "SoundLock"
            return image
        }

        return NSImage(systemSymbolName: "headphones",
                       accessibilityDescription: "SoundLock")
    }

    @objc private func handleApplicationDidResignActive(_ notification: Notification) {
        closePopover(notification)
    }

    @objc private func closePopover(_ sender: Any?) {
        guard let popover, popover.isShown else { return }
        popover.performClose(sender)
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            closePopover(sender)
            return
        }
        let screen = button.window?.screen ?? NSScreen.main
        let maxHeight = (screen?.visibleFrame.height ?? 800) - Constants.UI.popoverEdgeInset
        let ideal = hostingController?.sizeThatFits(
            in: NSSize(width: Constants.UI.popoverWidth, height: .greatestFiniteMagnitude)
        )
        let height = min(ideal?.height ?? Constants.UI.popoverDefaultHeight, maxHeight)
        popover.contentSize = NSSize(width: Constants.UI.popoverWidth, height: height)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}
