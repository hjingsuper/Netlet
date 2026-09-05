import Foundation
import Observation

@MainActor
@Observable
final class PreferencesStore {
    private enum Keys {
        static let menuDisplayStyle = "netlet.menu-display-style"
        static let speedUnitMode = "netlet.speed-unit-mode"
        static let decimalPlaces = "netlet.decimal-places"
        static let interfaceSelection = "netlet.interface-selection"
    }

    private(set) var menuDisplayStyle: MenuDisplayStyle
    private(set) var speedUnitMode: SpeedUnitMode
    private(set) var decimalPlaces: DecimalPlaces
    private(set) var interfaceSelection: InterfaceSelection
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuDisplayStyle = defaults.string(forKey: Keys.menuDisplayStyle)
            .flatMap(MenuDisplayStyle.init(rawValue:)) ?? .full
        speedUnitMode = defaults.string(forKey: Keys.speedUnitMode)
            .flatMap(SpeedUnitMode.init(rawValue:)) ?? .bytes
        decimalPlaces = DecimalPlaces(
            rawValue: defaults.object(forKey: Keys.decimalPlaces) as? Int ?? 1
        ) ?? .one
        interfaceSelection = InterfaceSelection(
            persistedValue: defaults.string(forKey: Keys.interfaceSelection)
        )
    }

    var monitorConfiguration: NetworkMonitorConfiguration {
        NetworkMonitorConfiguration(interfaceSelection: interfaceSelection)
    }

    func setMenuDisplayStyle(_ value: MenuDisplayStyle) {
        guard value != menuDisplayStyle else { return }
        menuDisplayStyle = value
        defaults.set(value.rawValue, forKey: Keys.menuDisplayStyle)
        onChange?()
    }

    func setSpeedUnitMode(_ value: SpeedUnitMode) {
        guard value != speedUnitMode else { return }
        speedUnitMode = value
        defaults.set(value.rawValue, forKey: Keys.speedUnitMode)
        onChange?()
    }

    func setDecimalPlaces(_ value: DecimalPlaces) {
        guard value != decimalPlaces else { return }
        decimalPlaces = value
        defaults.set(value.rawValue, forKey: Keys.decimalPlaces)
        onChange?()
    }

    func setInterfaceSelection(_ value: InterfaceSelection) {
        guard value != interfaceSelection else { return }
        interfaceSelection = value
        defaults.set(value.persistedValue, forKey: Keys.interfaceSelection)
        onChange?()
    }

    private let defaults: UserDefaults
}
