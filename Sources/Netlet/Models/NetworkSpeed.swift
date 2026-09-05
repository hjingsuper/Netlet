import Foundation

enum NetworkMonitorState: Equatable, Sendable {
    case connected
    case unavailable
}

struct NetworkInterfaceDescriptor: Equatable, Identifiable, Sendable {
    let id: String
    let systemName: String
    let localizedName: String

    init(systemName: String, localizedName: String) {
        id = systemName
        self.systemName = systemName
        self.localizedName = localizedName
    }
}

struct NetworkSpeedSnapshot: Equatable, Sendable {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let interfaceName: String?
    let state: NetworkMonitorState
    let sampledAt: Date

    static let initial = NetworkSpeedSnapshot(
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        interfaceName: nil,
        state: .unavailable,
        sampledAt: .now
    )
}

struct InterfaceByteCounters: Equatable, Sendable {
    let received: UInt64
    let sent: UInt64
}

struct SpeedSampleCalculator: Sendable {
    private var previousInterface: String?
    private var previousCounters: InterfaceByteCounters?
    private var previousUptimeNanoseconds: UInt64?

    mutating func reset() {
        previousInterface = nil
        previousCounters = nil
        previousUptimeNanoseconds = nil
    }

    mutating func record(
        interfaceName: String,
        counters: InterfaceByteCounters,
        uptimeNanoseconds: UInt64
    ) -> (download: Double, upload: Double) {
        defer {
            previousInterface = interfaceName
            previousCounters = counters
            previousUptimeNanoseconds = uptimeNanoseconds
        }

        guard
            previousInterface == interfaceName,
            let previousCounters,
            let previousUptimeNanoseconds,
            uptimeNanoseconds > previousUptimeNanoseconds,
            counters.received >= previousCounters.received,
            counters.sent >= previousCounters.sent
        else {
            return (0, 0)
        }

        let elapsed = Double(uptimeNanoseconds - previousUptimeNanoseconds) / 1_000_000_000
        guard elapsed > 0 else { return (0, 0) }

        return (
            Double(counters.received - previousCounters.received) / elapsed,
            Double(counters.sent - previousCounters.sent) / elapsed
        )
    }
}
