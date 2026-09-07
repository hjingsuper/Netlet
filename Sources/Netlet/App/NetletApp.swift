import AppKit
import OSLog
import Observation
import SwiftUI

@MainActor
@Observable
private final class SettingsVisibility {
    var isVisible = true
}

private struct VisibleSettingsContent: View {
    let visibility: SettingsVisibility
    let content: SettingsView

    var body: some View {
        Group {
            if visibility.isVisible { content } else { Color.clear }
        }
        .frame(minWidth: 860, minHeight: 700)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hjingsuper.Netlet",
        category: "Lifecycle"
    )
    private var monitor: NetworkSpeedMonitor?
    private var preferences: PreferencesStore?
    private var historyStore: TrafficHistoryStore?
    private var languageStore: LanguageStore?
    private var launchAtLoginManager: LaunchAtLoginManager?
    private var updateManager: UpdateManager?
    private var statusBarController: StatusBarController?
    private var windowController: NSWindowController?
    private let settingsVisibility = SettingsVisibility()
    private var isFinishingTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let preferences = PreferencesStore()
        let languageStore = LanguageStore()
        let monitor = NetworkSpeedMonitor()
        let historyStore = TrafficHistoryStore()
        let launchAtLoginManager = LaunchAtLoginManager()
        let updateManager = UpdateManager()
        let statusBarController = StatusBarController(
            monitor: monitor,
            preferences: preferences,
            historyStore: historyStore,
            languageStore: languageStore,
            updatesAvailable: updateManager.isAvailable,
            openSettings: { [weak self] in self?.showSettings() },
            checkForUpdates: { [weak updateManager] in updateManager?.checkForUpdates() }
        )

        self.preferences = preferences
        self.languageStore = languageStore
        self.monitor = monitor
        self.historyStore = historyStore
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
        monitor.onUpdate = { [weak statusBarController, weak historyStore, weak monitor] in
            statusBarController?.updateSnapshot()
            if let snapshot = monitor?.snapshot {
                historyStore?.ingest(snapshot)
            }
        }

        historyStore.start()
        monitor.start(configuration: preferences.monitorConfiguration)
        updateManager.start()
        logger.notice("Netlet services are ready")

#if DEBUG
        if ProcessInfo.processInfo.environment["NETLET_UI_PREVIEW"] == "1" {
            showSettings()
        }
#endif
        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak statusBarController] in
                statusBarController?.showMenuForTesting()
            }
        }
        if CommandLine.arguments.contains("--show-settings") {
            showSettings()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isFinishingTermination, let historyStore else {
            return .terminateNow
        }

        isFinishingTermination = true
        monitor?.stop()
        Task {
            await historyStore.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === windowController?.window else { return }
        let visible = window.occlusionState.contains(.visible)
        settingsVisibility.isVisible = visible
        historyStore?.setPresentationActive(visible, for: .settings)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === windowController?.window else { return }
        historyStore?.setPresentationActive(false, for: .settings)
        settingsVisibility.isVisible = false
        // Release the hosting tree after AppKit completes window teardown.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, !window.isVisible,
                  self.windowController?.window === window else { return }
            self.windowController = nil
        }
    }

    private func showSettings() {
        guard
            let monitor,
            let preferences,
            let historyStore,
            let languageStore,
            let launchAtLoginManager,
            let updateManager
        else { return }

        if windowController == nil {
            let rootView = SettingsView(
                monitor: monitor,
                preferences: preferences,
                historyStore: historyStore,
                languageStore: languageStore,
                launchAtLoginManager: launchAtLoginManager,
                updateManager: updateManager
            )
            let hostingController = NSHostingController(rootView: VisibleSettingsContent(
                visibility: settingsVisibility, content: rootView))
            let window = NSWindow(contentViewController: hostingController)
            window.delegate = self
            window.title = "Netlet"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 920, height: 720))
            window.contentMinSize = NSSize(width: 860, height: 700)
            window.isReleasedWhenClosed = false
            window.center()
            windowController = NSWindowController(window: window)
        }

        historyStore.setPresentationActive(true, for: .settings)
        settingsVisibility.isVisible = true
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
