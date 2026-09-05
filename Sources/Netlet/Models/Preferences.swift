import Foundation

enum MenuDisplayStyle: String, CaseIterable, Identifiable, Sendable {
    case full
    case compact
    case downloadOnly
    case uploadOnly

    var id: String { rawValue }
}

enum SpeedUnitMode: String, CaseIterable, Identifiable, Sendable {
    case bytes
    case bits

    var id: String { rawValue }
}

enum DecimalPlaces: Int, CaseIterable, Identifiable, Sendable {
    case zero = 0
    case one = 1
    case two = 2

    var id: Int { rawValue }
}

enum InterfaceSelection: Equatable, Sendable {
    case automatic
    case named(String)

    var persistedValue: String {
        switch self {
        case .automatic: "automatic"
        case let .named(name): "interface:\(name)"
        }
    }

    init(persistedValue: String?) {
        guard
            let persistedValue,
            persistedValue.hasPrefix("interface:"),
            !persistedValue.dropFirst("interface:".count).isEmpty
        else {
            self = .automatic
            return
        }
        self = .named(String(persistedValue.dropFirst("interface:".count)))
    }
}

struct NetworkMonitorConfiguration: Equatable, Sendable {
    let interfaceSelection: InterfaceSelection

    // A one-second cadence keeps the menu bar readable while avoiding needless
    // background work. It is deliberately not exposed as a preference.
    var refreshInterval: TimeInterval { 1 }
}
