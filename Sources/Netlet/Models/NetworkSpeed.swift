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
    let isRateSampleValid: Bool
    let downloadBytesDelta: UInt64
    let uploadBytesDelta: UInt64
    let sampleDuration: TimeInterval

    init(
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double,
        interfaceName: String?,
        state: NetworkMonitorState,
        sampledAt: Date,
        isRateSampleValid: Bool = false,
        downloadBytesDelta: UInt64 = 0,
        uploadBytesDelta: UInt64 = 0,
        sampleDuration: TimeInterval = 0
    ) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.interfaceName = interfaceName
        self.state = state
        self.sampledAt = sampledAt
        self.isRateSampleValid = isRateSampleValid
        self.downloadBytesDelta = downloadBytesDelta
        self.uploadBytesDelta = uploadBytesDelta
        self.sampleDuration = sampleDuration
    }

    static let initial = NetworkSpeedSnapshot(
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        interfaceName: nil,
        state: .unavailable,
        sampledAt: .now
    )
}

struct NetworkRateSample: Equatable, Sendable {
    let download: Double
    let upload: Double
    let downloadBytesDelta: UInt64
    let uploadBytesDelta: UInt64
    let duration: TimeInterval
    let isValid: Bool

    static let invalid = NetworkRateSample(
        download: 0,
        upload: 0,
        downloadBytesDelta: 0,
        uploadBytesDelta: 0,
        duration: 0,
        isValid: false
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
    ) -> NetworkRateSample {
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
            return .invalid
        }

        let elapsed = Double(uptimeNanoseconds - previousUptimeNanoseconds) / 1_000_000_000
        guard elapsed > 0 else { return .invalid }

        let downloadBytesDelta = counters.received - previousCounters.received
        let uploadBytesDelta = counters.sent - previousCounters.sent

        return NetworkRateSample(
            download: Double(downloadBytesDelta) / elapsed,
            upload: Double(uploadBytesDelta) / elapsed,
            downloadBytesDelta: downloadBytesDelta,
            uploadBytesDelta: uploadBytesDelta,
            duration: elapsed,
            isValid: true
        )
    }
}
