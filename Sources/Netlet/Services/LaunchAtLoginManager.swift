import AppKit
import Foundation
import Observation
import OSLog
import ServiceManagement

enum LaunchAtLoginStatus {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
    case failed
}

@MainActor
@Observable
final class LaunchAtLoginManager {
    private enum Keys {
        static let requested = "netlet.launch-at-login"
    }

    private(set) var isEnabled: Bool
    private(set) var status: LaunchAtLoginStatus = .disabled

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.object(forKey: Keys.requested) as? Bool
        isEnabled = storedValue ?? true
        if storedValue == nil {
            defaults.set(true, forKey: Keys.requested)
        }

#if DEBUG
        if ProcessInfo.processInfo.environment["NETLET_UI_PREVIEW"] == "1" {
            status = isEnabled ? .enabled : .disabled
            return
        }
#endif

        applyRequestedState()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Keys.requested)
        applyRequestedState()
    }

    func retryRegistration() {
        applyRequestedState()
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private let defaults: UserDefaults
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hjingsuper.Netlet",
        category: "LaunchAtLogin"
    )

    private func applyRequestedState() {
        guard isInstalledInApplications else {
            status = isEnabled ? .unavailable : .disabled
            return
        }

        do {
            if isEnabled {
                switch SMAppService.mainApp.status {
                case .notRegistered, .notFound:
                    try SMAppService.mainApp.register()
                case .enabled, .requiresApproval:
                    break
                @unknown default:
                    break
                }
            } else {
                switch SMAppService.mainApp.status {
                case .enabled, .requiresApproval:
                    try SMAppService.mainApp.unregister()
                case .notRegistered, .notFound:
                    break
                @unknown default:
                    break
                }
            }
            updateStatus()
        } catch {
            status = .failed
            logger.error(
                "Failed to update login item: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func updateStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            status = .enabled
        case .requiresApproval:
            status = .requiresApproval
        case .notRegistered:
            status = isEnabled ? .failed : .disabled
        case .notFound:
            status = isEnabled ? .unavailable : .disabled
        @unknown default:
            status = .unavailable
        }
    }

    private var isInstalledInApplications: Bool {
        let bundlePath = Bundle.main.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        let roots = [
            "/Applications",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true).path,
        ]
        return roots.contains { bundlePath.hasPrefix($0 + "/") }
    }
}
