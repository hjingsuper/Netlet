import AppKit
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hjingsuper.Netlet",
        category: "Lifecycle"
    )
    private var monitor: NetworkSpeedMonitor?
    private var preferences: PreferencesStore?
    private var languageStore: LanguageStore?
    private var launchAtLoginManager: LaunchAtLoginManager?
    private var updateManager: UpdateManager?
    private var statusBarController: StatusBarController?
    private var windowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let preferences = PreferencesStore()
        let languageStore = LanguageStore()
        let monitor = NetworkSpeedMonitor()
        let launchAtLoginManager = LaunchAtLoginManager()
        let updateManager = UpdateManager()
        let statusBarController = StatusBarController(
            monitor: monitor,
            preferences: preferences,
            languageStore: languageStore,
            updatesAvailable: updateManager.isAvailable,
            openSettings: { [weak self] in self?.showSettings() },
            checkForUpdates: { [weak updateManager] in updateManager?.checkForUpdates() }
        )

        self.preferences = preferences
        self.languageStore = languageStore
        self.monitor = monitor
        self.launchAtLoginManager = launchAtLoginManager
        self.updateManager = updateManager
        self.statusBarController = statusBarController

        var activeMonitorConfiguration = preferences.monitorConfiguration
        preferences.onChange = { [weak monitor, weak statusBarController, weak preferences] in
            guard let preferences else { return }
            let newConfiguration = preferences.monitorConfiguration
            if newConfiguration != activeMonitorConfiguration {
                activeMonitorConfiguration = newConfiguration
                monitor?.reconfigure(newConfiguration)
            }
            statusBarController?.preferencesDidChange()
        }
        languageStore.onChange = { [weak statusBarController] in
            statusBarController?.languageDidChange()
        }
        monitor.onUpdate = { [weak statusBarController] in
            statusBarController?.updateSnapshot()
        }

        monitor.start(configuration: preferences.monitorConfiguration)
        updateManager.start()
        logger.notice("Netlet services are ready")

#if DEBUG
        if ProcessInfo.processInfo.environment["NETLET_UI_PREVIEW"] == "1" {
            showSettings()
        }
        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak statusBarController] in
                statusBarController?.showMenuForTesting()
            }
        }
#endif
        if CommandLine.arguments.contains("--show-settings") {
            showSettings()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showSettings() {
        guard
            let monitor,
            let preferences,
            let languageStore,
            let launchAtLoginManager,
            let updateManager
        else { return }

        if windowController == nil {
            let rootView = SettingsView(
                monitor: monitor,
                preferences: preferences,
                languageStore: languageStore,
                launchAtLoginManager: launchAtLoginManager,
                updateManager: updateManager
            )
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Netlet"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 820, height: 480))
            window.contentMinSize = NSSize(width: 760, height: 460)
            window.isReleasedWhenClosed = false
            window.center()
            windowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }
}

@main
@MainActor
enum NetletApp {
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.run()
        _ = appDelegate
    }
}
