import AppKit
import OSLog
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    init(
        monitor: NetworkSpeedMonitor,
        preferences: PreferencesStore,
        historyStore: TrafficHistoryStore,
        languageStore: LanguageStore,
        updatesAvailable: Bool,
        openSettings: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.preferences = preferences
        self.historyStore = historyStore
        self.languageStore = languageStore
        self.updatesAvailable = updatesAvailable
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates
        super.init()

        menu.delegate = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.installStatusItem()
        }
    }

    private let monitor: NetworkSpeedMonitor
    private let preferences: PreferencesStore
    private let historyStore: TrafficHistoryStore
    private let languageStore: LanguageStore
    private let updatesAvailable: Bool
    private let openSettings: () -> Void
    private let checkForUpdates: () -> Void
    private let menu = NSMenu()
    private var statusItem: NSStatusItem?
    private var menuIsOpen = false
    private static let statusFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let statusHorizontalPadding: CGFloat = 10
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hjingsuper.Netlet",
        category: "MenuBar"
    )

    func updateSnapshot() {
        updateStatusTitle()
    }

    func preferencesDidChange() {
        updateStatusLayout()
        updateStatusTitle()
        rebuildMenu()
    }

    func languageDidChange() {
        rebuildMenu()
    }

    func showMenuForTesting() {
        guard let button = statusItem?.button else { return }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 2),
            in: button
        )
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: preferredStatusItemLength)
        item.autosaveName = "com.hjingsuper.Netlet.primary-status-item"
        item.button?.font = Self.statusFont
        item.button?.alignment = .center
        item.button?.image = nil
        item.button?.imagePosition = .noImage
        item.button?.title = SpeedFormatter.stableStatusTitle(
            snapshot: .initial,
            style: preferences.menuDisplayStyle,
            unitMode: preferences.speedUnitMode,
            decimalPlaces: preferences.decimalPlaces
        )
        item.button?.toolTip = "Netlet"
        item.menu = menu
        item.isVisible = true
        statusItem = item
        updateStatusTitle()
        rebuildMenu()
        logger.notice("Created the Netlet status item")
    }

    private func updateStatusTitle() {
        guard let statusItem else { return }
        let title = SpeedFormatter.stableStatusTitle(
            snapshot: monitor.snapshot,
            style: preferences.menuDisplayStyle,
            unitMode: preferences.speedUnitMode,
            decimalPlaces: preferences.decimalPlaces,
            scalePair: monitor.scalePair(for: preferences.speedUnitMode)
        )
        if statusItem.button?.title != title { statusItem.button?.title = title }
        let tooltip = interfaceDescription
        if statusItem.button?.toolTip != tooltip { statusItem.button?.toolTip = tooltip }
        if !statusItem.isVisible { statusItem.isVisible = true }
    }

    private func updateStatusLayout() {
        statusItem?.length = preferredStatusItemLength
    }

    private var preferredStatusItemLength: CGFloat {
        let placeholder = SpeedFormatter.stableStatusTitle(
            snapshot: .initial,
            style: preferences.menuDisplayStyle,
            unitMode: preferences.speedUnitMode,
            decimalPlaces: preferences.decimalPlaces
        )
        let textWidth = (placeholder as NSString).size(
            withAttributes: [.font: Self.statusFont]
        ).width
        return ceil(textWidth + Self.statusHorizontalPadding)
    }

    private var interfaceDescription: String {
        guard let interfaceName = monitor.snapshot.interfaceName else {
            return languageStore[.networkUnavailable]
        }
        let displayName = monitor.availableInterfaces
            .first { $0.systemName == interfaceName }?.localizedName ?? interfaceName
        return "\(displayName) · \(interfaceName)"
    }

    private func rebuildMenu() {
        guard statusItem != nil else { return }
        menu.removeAllItems()

        let speedItem = NSMenuItem()
        speedItem.view = NSView(frame: NSRect(x: 0, y: 0,
            width: SpeedMenuView.preferredWidth, height: SpeedMenuView.preferredHeight))
        menu.addItem(speedItem)
        if menuIsOpen { attachLiveMenuView() }
        menu.addItem(.separator())

        addMenuActions()
    }

    private func attachLiveMenuView() {
        let speedView = SpeedMenuView(
            monitor: monitor,
            preferences: preferences,
            historyStore: historyStore,
            languageStore: languageStore
        )
        let hostingView = NSHostingView(rootView: speedView)
        // This menu owns its fixed size; avoid repeated SwiftUI size probes.
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: SpeedMenuView.preferredWidth,
            height: SpeedMenuView.preferredHeight
        )
        menu.items.first?.view = hostingView
    }

    private func addMenuActions() {
        let settings = NSMenuItem(
            title: languageStore[.preferences],
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        if updatesAvailable {
            let update = NSMenuItem(
                title: languageStore[.checkForUpdates],
                action: #selector(checkForUpdatesNow),
                keyEquivalent: ""
            )
            update.target = self
            menu.addItem(update)
        }

        let github = NSMenuItem(
            title: languageStore[.github],
            action: #selector(openGitHub),
            keyEquivalent: ""
        )
        github.target = self
        menu.addItem(github)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: languageStore[.quit],
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        historyStore.setPresentationActive(true, for: .menu)
        attachLiveMenuView()
        updateStatusTitle()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        historyStore.setPresentationActive(false, for: .menu)
        // Detach the entire hosting tree, not just its pixels. Hidden charts
        // must not retain live Observation subscriptions between menu visits.
        menu.items.first?.view = NSView(frame: NSRect(x: 0, y: 0,
            width: SpeedMenuView.preferredWidth, height: SpeedMenuView.preferredHeight))
    }

    @objc private func openPreferences() {
        openSettings()
    }

    @objc private func checkForUpdatesNow() {
        checkForUpdates()
    }

    @objc private func openGitHub() {
        guard let url = URL(string: "https://github.com/hjingsuper/Netlet") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

}
