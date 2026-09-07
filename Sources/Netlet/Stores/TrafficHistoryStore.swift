import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class TrafficHistoryStore {
    @ObservationIgnored private(set) var records: [TrafficMinuteRecord] = []
    @ObservationIgnored private(set) var liveRecord: TrafficMinuteRecord?
    private(set) var presentationDate = Date.now
    enum PresentationConsumer: Hashable { case menu, settings }
    @ObservationIgnored private var consumers: Set<PresentationConsumer> = []
    @ObservationIgnored private var presentationCache: [TrafficHistoryRange: [TrafficMinuteRecord]] = [:]
    @ObservationIgnored private var segmentCache: [String: [[TrafficMinuteRecord]]] = [:]

    func setPresentationActive(_ active: Bool, for consumer: PresentationConsumer, now: Date = .now) {
        if active { consumers.insert(consumer) } else { consumers.remove(consumer) }
        if active { publishPresentation(now: now, force: true) }
        if consumers.isEmpty {
            presentationCache.removeAll()
            segmentCache.removeAll()
        }
    }

    private func publishPresentation(now: Date, force: Bool = false) {
        guard force || (!consumers.isEmpty && abs(now.timeIntervalSince(presentationDate)) >= 5) else { return }
        presentationCache.removeAll(keepingCapacity: true)
        segmentCache.removeAll(keepingCapacity: true)
        presentationDate = now
    }

    func presentationRecords(for range: TrafficHistoryRange) -> [TrafficMinuteRecord] {
        let now = presentationDate // The only clock dependency of history UI.
        if let cached = presentationCache[range] { return cached }
        let result = recentRecords(for: range, now: now)
        presentationCache[range] = result
        return result
    }

    func presentationSegments(for range: TrafficHistoryRange, maximumPointCount: Int) -> [[TrafficMinuteRecord]] {
        _ = presentationDate
        let budget = max(1, min(600, maximumPointCount))
        let key = "\(range)-\(budget)"
        if let cached = segmentCache[key] { return cached }
        let result = TrafficHistoryDownsampler.segments(from: presentationRecords(for: range), maximumPointCount: budget)
        // Resizing must not create an unbounded cache of width-specific charts.
        if segmentCache.count >= 4 { segmentCache.removeAll(keepingCapacity: true) }
        segmentCache[key] = result
        return result
    }
    private(set) var selectedRange: TrafficHistoryRange = .oneHour
    private(set) var isLoading = false
    private(set) var isAvailable = true

    init(databaseURL: URL? = nil) {
        do {
            let resolvedURL = try databaseURL ?? TrafficHistoryDatabase.defaultURL()
            database = try TrafficHistoryDatabase(url: resolvedURL)
        } catch {
            database = nil
            isAvailable = false
            logger.error("Unable to open traffic history: \(String(describing: error), privacy: .public)")
        }
    }

    func start(now: Date = .now) {
        refresh(now: now, pruneFirst: true)
    }

    func ingest(_ snapshot: NetworkSpeedSnapshot) {
        let completed = accumulator.consume(snapshot)
        liveRecord = accumulator.currentRecord
        publishPresentation(now: snapshot.sampledAt)
        guard let completed else { return }
        persist(completed, now: snapshot.sampledAt)
    }

    func selectRange(_ range: TrafficHistoryRange) {
        guard range != selectedRange else { return }
        selectedRange = range
        publishPresentation(now: .now, force: true)
    }

    func clearHistory() {
        accumulator.reset()
        liveRecord = nil
        records = []
        publishPresentation(now: .now, force: true)
        guard let database else { return }

        operationGeneration &+= 1
        operationTask?.cancel()
        writeGeneration &+= 1
        let expectedWriteGeneration = writeGeneration
        let previousWrite = writeTask
        writeTask = Task { [weak self] in
            await previousWrite?.value
            do {
                try await database.clear()
                guard self?.writeGeneration == expectedWriteGeneration else { return }
                self?.isAvailable = true
                self?.writeTask = nil
            } catch {
                guard self?.writeGeneration == expectedWriteGeneration else { return }
                self?.markUnavailable(error)
                self?.writeTask = nil
            }
        }
    }

    func flush(now: Date = .now) async {
        let record = accumulator.finish()
        liveRecord = nil
        await writeTask?.value
        guard let record else { return }
        guard let database else { return }

        do {
            try await database.upsertAndPrune(record, now: now)
        } catch {
            markUnavailable(error)
        }
    }

    var visibleRecords: [TrafficMinuteRecord] {
        presentationRecords(for: selectedRange)
    }

    func recentRecords(
        for range: TrafficHistoryRange,
        now: Date = .now
    ) -> [TrafficMinuteRecord] {
        let cutoff = now.addingTimeInterval(-range.duration)
        var result = records.filter { $0.timestamp >= cutoff }
        if let liveRecord, liveRecord.timestamp >= cutoff {
            if let index = result.firstIndex(where: { $0.timestamp == liveRecord.timestamp }) {
                result[index] = result[index].merging(liveRecord)
            } else {
                result.append(liveRecord)
            }
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    var summary: TrafficHistorySummary {
        visibleRecords.reduce(into: .empty) { summary, record in
            summary = TrafficHistorySummary(
                downloadBytes: addingClamped(summary.downloadBytes, record.downloadBytes),
                uploadBytes: addingClamped(summary.uploadBytes, record.uploadBytes),
                peakDownloadBytesPerSecond: max(
                    summary.peakDownloadBytesPerSecond,
                    record.peakDownloadBytesPerSecond
                ),
                peakUploadBytesPerSecond: max(
                    summary.peakUploadBytesPerSecond,
                    record.peakUploadBytesPerSecond
                )
            )
        }
    }

    private let database: TrafficHistoryDatabase?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.hjingsuper.Netlet",
        category: "History"
    )
    private var accumulator = MinuteTrafficAccumulator()
    private var operationGeneration: UInt64 = 0
    private var operationTask: Task<Void, Never>?
    private var writeGeneration: UInt64 = 0
    private var writeTask: Task<Void, Never>?

    private func persist(_ record: TrafficMinuteRecord, now: Date) {
        guard let database else { return }
        writeGeneration &+= 1
        let expectedWriteGeneration = writeGeneration
        let previousWrite = writeTask
        writeTask = Task { [weak self] in
            await previousWrite?.value
            do {
                try await database.upsertAndPrune(record, now: now)
                guard self?.writeGeneration == expectedWriteGeneration else { return }
                await self?.reloadAfterWrite(now: now)
                self?.writeTask = nil
            } catch {
                guard self?.writeGeneration == expectedWriteGeneration else { return }
                self?.markUnavailable(error)
                self?.writeTask = nil
            }
        }
    }

    private func reloadAfterWrite(now: Date) async {
        guard let database else { return }
        do {
            let loaded = try await database.records(
                since: now.addingTimeInterval(-TrafficHistoryDatabase.retentionDuration),
                through: now
            )
            records = loaded
            publishPresentation(now: .now, force: !consumers.isEmpty)
            isAvailable = true
        } catch {
            markUnavailable(error)
        }
    }

    private func refresh(now: Date, pruneFirst: Bool = false) {
        guard let database else { return }
        operationGeneration &+= 1
        let expectedGeneration = operationGeneration
        isLoading = true
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            do {
                if pruneFirst {
                    try await database.prune(now: now)
                }
                let loaded = try await database.records(
                    since: now.addingTimeInterval(-TrafficHistoryDatabase.retentionDuration),
                    through: now
                )
                guard
                    !Task.isCancelled,
                    self?.operationGeneration == expectedGeneration
                else { return }
                self?.records = loaded
                self?.publishPresentation(now: now, force: true)
                self?.isLoading = false
                self?.isAvailable = true
            } catch {
                guard !Task.isCancelled, self?.operationGeneration == expectedGeneration else { return }
                self?.isLoading = false
                self?.markUnavailable(error)
            }
        }
    }

    private func markUnavailable(_ error: Error) {
        isAvailable = false
        isLoading = false
        logger.error("Traffic history operation failed: \(String(describing: error), privacy: .public)")
    }

    private func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : value
    }
}

enum TrafficHistoryDownsampler {
    static func segments(
        from records: [TrafficMinuteRecord],
        maximumPointCount: Int,
        gapTolerance: TimeInterval = 90
    ) -> [[TrafficMinuteRecord]] {
        guard !records.isEmpty, maximumPointCount > 0 else { return [] }

        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        var sourceSegments: [[TrafficMinuteRecord]] = []
        for record in sorted {
            if
                let lastTimestamp = sourceSegments.last?.last?.timestamp,
                record.timestamp.timeIntervalSince(lastTimestamp) <= gapTolerance
            {
                sourceSegments[sourceSegments.count - 1].append(record)
            } else {
                sourceSegments.append([record])
            }
        }

        if sourceSegments.count >= maximumPointCount {
            return evenlySelected(sourceSegments, count: maximumPointCount).compactMap { segment in
                segment.last.map { [$0] }
            }
        }

        let totalRecordCount = max(1, sourceSegments.reduce(0) { $0 + $1.count })
        var remainingBudget = maximumPointCount
        var result: [[TrafficMinuteRecord]] = []

        for (index, segment) in sourceSegments.enumerated() {
            let remainingSegments = sourceSegments.count - index - 1
            let proportional = Int(
                (Double(segment.count) / Double(totalRecordCount) * Double(maximumPointCount)).rounded()
            )
            let budget = min(
                segment.count,
                max(1, min(proportional, remainingBudget - remainingSegments))
            )
            result.append(downsample(segment, to: budget))
            remainingBudget -= budget
        }
        return result
    }

    private static func downsample(
        _ records: [TrafficMinuteRecord],
        to pointCount: Int
    ) -> [TrafficMinuteRecord] {
        guard records.count > pointCount, pointCount > 0 else { return records }

        return (0..<pointCount).map { bucketIndex in
            let lower = bucketIndex * records.count / pointCount
            let upper = max(lower + 1, (bucketIndex + 1) * records.count / pointCount)
            let bucket = records[lower..<min(upper, records.count)]
            let totalSamples = max(1, bucket.reduce(0) { $0 + $1.sampleCount })
            let weightedDownload = bucket.reduce(0.0) {
                $0 + $1.averageDownloadBytesPerSecond * Double($1.sampleCount)
            }
            let weightedUpload = bucket.reduce(0.0) {
                $0 + $1.averageUploadBytesPerSecond * Double($1.sampleCount)
            }
            return TrafficMinuteRecord(
                timestamp: bucket[bucket.index(bucket.startIndex, offsetBy: bucket.count / 2)].timestamp,
                averageDownloadBytesPerSecond: weightedDownload / Double(totalSamples),
                averageUploadBytesPerSecond: weightedUpload / Double(totalSamples),
                peakDownloadBytesPerSecond: bucket.map(\.peakDownloadBytesPerSecond).max() ?? 0,
                peakUploadBytesPerSecond: bucket.map(\.peakUploadBytesPerSecond).max() ?? 0,
                sampleCount: totalSamples,
                downloadBytes: bucket.reduce(0) { addingClamped($0, $1.downloadBytes) },
                uploadBytes: bucket.reduce(0) { addingClamped($0, $1.uploadBytes) }
            )
        }
    }

    private static func evenlySelected<T>(_ values: [T], count: Int) -> [T] {
        guard values.count > count, count > 0 else { return values }
        if count == 1 { return [values[values.count / 2]] }
        return (0..<count).map { index in
            let sourceIndex = index * (values.count - 1) / (count - 1)
            return values[sourceIndex]
        }
    }

    private static func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : value
    }
}
