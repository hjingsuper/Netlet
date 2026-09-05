import Foundation

struct TrafficMinuteRecord: Equatable, Identifiable, Sendable {
    let timestamp: Date
    let averageDownloadBytesPerSecond: Double
    let averageUploadBytesPerSecond: Double
    let peakDownloadBytesPerSecond: Double
    let peakUploadBytesPerSecond: Double
    let sampleCount: Int
    let downloadBytes: UInt64
    let uploadBytes: UInt64

    var id: TimeInterval { timestamp.timeIntervalSince1970 }

    func merging(_ other: TrafficMinuteRecord) -> TrafficMinuteRecord {
        let ownCount = max(0, sampleCount)
        let otherCount = max(0, other.sampleCount)
        let combinedCount = max(1, ownCount + otherCount)

        return TrafficMinuteRecord(
            timestamp: min(timestamp, other.timestamp),
            averageDownloadBytesPerSecond: (
                averageDownloadBytesPerSecond * Double(ownCount)
                    + other.averageDownloadBytesPerSecond * Double(otherCount)
            ) / Double(combinedCount),
            averageUploadBytesPerSecond: (
                averageUploadBytesPerSecond * Double(ownCount)
                    + other.averageUploadBytesPerSecond * Double(otherCount)
            ) / Double(combinedCount),
            peakDownloadBytesPerSecond: max(
                peakDownloadBytesPerSecond,
                other.peakDownloadBytesPerSecond
            ),
            peakUploadBytesPerSecond: max(
                peakUploadBytesPerSecond,
                other.peakUploadBytesPerSecond
            ),
            sampleCount: combinedCount,
            downloadBytes: Self.addingClamped(downloadBytes, other.downloadBytes),
            uploadBytes: Self.addingClamped(uploadBytes, other.uploadBytes)
        )
    }

    private static func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : value
    }
}

enum TrafficHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case oneHour
    case twentyFourHours
    case sevenDays

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .oneHour: 60 * 60
        case .twentyFourHours: 24 * 60 * 60
        case .sevenDays: 7 * 24 * 60 * 60
        }
    }
}

struct TrafficHistorySummary: Equatable, Sendable {
    let downloadBytes: UInt64
    let uploadBytes: UInt64
    let peakDownloadBytesPerSecond: Double
    let peakUploadBytesPerSecond: Double

    static let empty = TrafficHistorySummary(
        downloadBytes: 0,
        uploadBytes: 0,
        peakDownloadBytesPerSecond: 0,
        peakUploadBytesPerSecond: 0
    )
}

enum TrafficHistorySelection {
    static func nearest(
        to date: Date,
        in sortedRecords: [TrafficMinuteRecord]
    ) -> TrafficMinuteRecord? {
        guard !sortedRecords.isEmpty else { return nil }

        var lowerBound = 0
        var upperBound = sortedRecords.count
        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if sortedRecords[midpoint].timestamp < date {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        if lowerBound == 0 { return sortedRecords[0] }
        if lowerBound == sortedRecords.count { return sortedRecords[sortedRecords.count - 1] }

        let before = sortedRecords[lowerBound - 1]
        let after = sortedRecords[lowerBound]
        return date.timeIntervalSince(before.timestamp) <= after.timestamp.timeIntervalSince(date)
            ? before
            : after
    }
}

struct MinuteTrafficAccumulator: Sendable {
    private(set) var currentMinute: Date?
    private var downloadBytes: UInt64 = 0
    private var uploadBytes: UInt64 = 0
    private var validDuration: TimeInterval = 0
    private var peakDownloadBytesPerSecond: Double = 0
    private var peakUploadBytesPerSecond: Double = 0
    private var sampleCount = 0

    mutating func consume(_ snapshot: NetworkSpeedSnapshot) -> TrafficMinuteRecord? {
        let minute = Self.minuteStart(for: snapshot.sampledAt)
        var completedRecord: TrafficMinuteRecord?

        if currentMinute != minute {
            completedRecord = currentRecord
            begin(minute: minute)
        }

        guard snapshot.state == .connected, snapshot.isRateSampleValid else {
            return completedRecord
        }

        downloadBytes = addingClamped(downloadBytes, snapshot.downloadBytesDelta)
        uploadBytes = addingClamped(uploadBytes, snapshot.uploadBytesDelta)
        validDuration += max(0, snapshot.sampleDuration)
        peakDownloadBytesPerSecond = max(
            peakDownloadBytesPerSecond,
            snapshot.downloadBytesPerSecond
        )
        peakUploadBytesPerSecond = max(
            peakUploadBytesPerSecond,
            snapshot.uploadBytesPerSecond
        )
        sampleCount += 1
        return completedRecord
    }

    var currentRecord: TrafficMinuteRecord? {
        guard
            let currentMinute,
            sampleCount > 0,
            validDuration > 0
        else { return nil }

        return TrafficMinuteRecord(
            timestamp: currentMinute,
            averageDownloadBytesPerSecond: Double(downloadBytes) / validDuration,
            averageUploadBytesPerSecond: Double(uploadBytes) / validDuration,
            peakDownloadBytesPerSecond: peakDownloadBytesPerSecond,
            peakUploadBytesPerSecond: peakUploadBytesPerSecond,
            sampleCount: sampleCount,
            downloadBytes: downloadBytes,
            uploadBytes: uploadBytes
        )
    }

    mutating func finish() -> TrafficMinuteRecord? {
        defer { reset() }
        return currentRecord
    }

    mutating func reset() {
        currentMinute = nil
        downloadBytes = 0
        uploadBytes = 0
        validDuration = 0
        peakDownloadBytesPerSecond = 0
        peakUploadBytesPerSecond = 0
        sampleCount = 0
    }

    static func minuteStart(for date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60)
    }

    private mutating func begin(minute: Date) {
        reset()
        currentMinute = minute
    }

    private func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : value
    }
}
