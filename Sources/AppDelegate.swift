import Cocoa
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var hostingController: NSHostingController<AnyView>?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var guardStateObserver: AnyCancellable?

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
        observeGuardState()

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
        popover?.animates = false
        popover?.behavior = .transient
        popover?.contentViewController = hc
        popover?.delegate = self

        monitor.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        stopEventMonitors()
        closePopover(notification)
        monitor.stopMonitoring()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = statusBarImage(locked: monitor.guardEnabled)
            button.imageScaling = .scaleProportionallyUpOrDown
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    private func observeGuardState() {
        guardStateObserver = monitor.$guardEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locked in
                self?.statusItem?.button?.image = self?.statusBarImage(locked: locked)
            }
    }

    private func statusBarImage(locked: Bool) -> NSImage? {
        let resource = locked ? "StatusIcon" : "StatusIconUnlocked"
        let description = locked ? "SoundLock — locked" : "SoundLock — unlocked"

        if let path = Bundle.main.path(forResource: resource, ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            image.isTemplate = true
            image.size = NSSize(width: 24, height: 24)
            image.accessibilityDescription = description
            return image
        }

        return NSImage(systemSymbolName: locked ? "lock.fill" : "lock.open",
                       accessibilityDescription: description)
    }

    @objc private func handleApplicationDidResignActive(_ notification: Notification) {
        closePopover(notification)
    }

    @objc private func closePopover(_ sender: Any?) {
        guard let popover, popover.isShown else { return }
        stopEventMonitors()
        popover.performClose(sender)
    }

    private func startEventMonitors() {
        stopEventMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.closePopover(nil)
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, let popover = self.popover, popover.isShown else { return event }
            guard let eventWindow = event.window else { return event }

            let popoverWindow = popover.contentViewController?.view.window
            let statusWindow = self.statusItem?.button?.window
            if eventWindow === popoverWindow || eventWindow === statusWindow {
                return event
            }

            self.closePopover(nil)
            return event
        }
    }

    private func stopEventMonitors() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopEventMonitors()
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
        startEventMonitors()
        NSApp.activate(ignoringOtherApps: true)
    }
}
