import Foundation
import XCTest
@testable import Netlet

final class NetletTests: XCTestCase {
    func testFirstCounterSampleProducesZeroRates() {
        var calculator = SpeedSampleCalculator()
        let result = calculator.record(
            interfaceName: "en0",
            counters: InterfaceByteCounters(received: 10_000, sent: 2_000),
            uptimeNanoseconds: 1_000_000_000
        )

        XCTAssertEqual(result.download, 0)
        XCTAssertEqual(result.upload, 0)
        XCTAssertFalse(result.isValid)
    }

    func testCounterDeltasAreConvertedToRatesUsingMonotonicTime() {
        var calculator = SpeedSampleCalculator()
        _ = calculator.record(
            interfaceName: "en0",
            counters: InterfaceByteCounters(received: 1_000, sent: 500),
            uptimeNanoseconds: 1_000_000_000
        )
        let result = calculator.record(
            interfaceName: "en0",
            counters: InterfaceByteCounters(received: 5_096, sent: 2_548),
            uptimeNanoseconds: 3_000_000_000
        )

        XCTAssertEqual(result.download, 2_048, accuracy: 0.001)
        XCTAssertEqual(result.upload, 1_024, accuracy: 0.001)
        XCTAssertEqual(result.downloadBytesDelta, 4_096)
        XCTAssertEqual(result.uploadBytesDelta, 2_048)
        XCTAssertEqual(result.duration, 2, accuracy: 0.001)
        XCTAssertTrue(result.isValid)
    }

    func testChangingInterfaceResetsTheBaseline() {
        var calculator = SpeedSampleCalculator()
        _ = calculator.record(
            interfaceName: "en0",
            counters: InterfaceByteCounters(received: 100, sent: 100),
            uptimeNanoseconds: 1_000_000_000
        )
        let result = calculator.record(
            interfaceName: "utun3",
            counters: InterfaceByteCounters(received: 5_000_000, sent: 5_000_000),
            uptimeNanoseconds: 2_000_000_000
        )

        XCTAssertEqual(result.download, 0)
        XCTAssertEqual(result.upload, 0)
        XCTAssertFalse(result.isValid)
    }

    func testCounterRollbackResetsInsteadOfUnderflowing() {
        var calculator = SpeedSampleCalculator()
        _ = calculator.record(
            interfaceName: "en0",
            counters: InterfaceByteCounters(received: 10_000, sent: 10_000),
            uptimeNanoseconds: 1_000_000_000
        )
        let result = calculator.record(
            interfaceName: "en0",
            counters: InterfaceByteCounters(received: 20, sent: 30),
            uptimeNanoseconds: 2_000_000_000
        )

        XCTAssertEqual(result.download, 0)
        XCTAssertEqual(result.upload, 0)
        XCTAssertFalse(result.isValid)
    }

    func testByteFormattingUsesBinaryScaling() {
        let value = SpeedFormatter.valueAndUnit(
            bytesPerSecond: 1_572_864,
            unitMode: .bytes,
            decimalPlaces: .one
        )

        XCTAssertEqual(value.value, "1.5")
        XCTAssertEqual(value.unit, "MB/s")
    }

    func testBitFormattingUsesDecimalScaling() {
        let value = SpeedFormatter.valueAndUnit(
            bytesPerSecond: 125_000,
            unitMode: .bits,
            decimalPlaces: .zero
        )

        XCTAssertEqual(value.value, "1")
        XCTAssertEqual(value.unit, "Mbps")
    }

    func testSwitchingFromBytesToBitsAppliesAnEightTimesConversion() {
        let byteValue = SpeedFormatter.valueAndUnit(
            bytesPerSecond: 1_048_576,
            unitMode: .bytes,
            decimalPlaces: .one
        )
        let bitValue = SpeedFormatter.valueAndUnit(
            bytesPerSecond: 1_048_576,
            unitMode: .bits,
            decimalPlaces: .one
        )

        XCTAssertEqual(byteValue.value, "1.0")
        XCTAssertEqual(byteValue.unit, "MB/s")
        XCTAssertEqual(bitValue.value, "8.4")
        XCTAssertEqual(bitValue.unit, "Mbps")
    }

    func testScaleHysteresisPreventsFlappingAroundOneMegabyte() {
        var scale = SpeedScaleHysteresis()

        XCTAssertEqual(scale.update(value: 1_048_576, base: 1_024, maximumIndex: 3), 2)
        XCTAssertEqual(scale.update(value: 1_000_000, base: 1_024, maximumIndex: 3), 2)
        XCTAssertEqual(scale.update(value: 990_000, base: 1_024, maximumIndex: 3), 1)
        XCTAssertEqual(scale.update(value: 1_020_000, base: 1_024, maximumIndex: 3), 1)
        XCTAssertEqual(scale.update(value: 1_110_000, base: 1_024, maximumIndex: 3), 2)
    }

    func testFormatterCanUseAStabilizedScalePair() {
        let snapshot = NetworkSpeedSnapshot(
            downloadBytesPerSecond: 1_000_000,
            uploadBytesPerSecond: 512,
            interfaceName: "en0",
            state: .connected,
            sampledAt: .now
        )

        XCTAssertEqual(
            SpeedFormatter.statusTitle(
                snapshot: snapshot,
                style: .full,
                unitMode: .bytes,
                decimalPlaces: .one,
                scalePair: SpeedScalePair(downloadIndex: 1, uploadIndex: 0)
            ),
            "↓ 976.6 KB/s  ↑ 512.0 B/s"
        )
    }

    func testStatusTitleStyles() {
        let snapshot = NetworkSpeedSnapshot(
            downloadBytesPerSecond: 1_572_864,
            uploadBytesPerSecond: 131_072,
            interfaceName: "en0",
            state: .connected,
            sampledAt: .now
        )

        XCTAssertEqual(
            SpeedFormatter.statusTitle(
                snapshot: snapshot,
                style: .full,
                unitMode: .bytes,
                decimalPlaces: .one
            ),
            "↓ 1.5 MB/s  ↑ 128.0 KB/s"
        )
        XCTAssertEqual(
            SpeedFormatter.statusTitle(
                snapshot: snapshot,
                style: .compact,
                unitMode: .bytes,
                decimalPlaces: .one
            ),
            "↓1.5M  ↑128.0K"
        )
    }

    func testUnavailableStatusNeverLooksLikeARealZeroReading() {
        XCTAssertEqual(
            SpeedFormatter.statusTitle(
                snapshot: .initial,
                style: .full,
                unitMode: .bytes,
                decimalPlaces: .one
            ),
            "↓ —  ↑ —"
        )
    }

    func testInterfaceSelectionRoundTrips() {
        XCTAssertEqual(InterfaceSelection(persistedValue: nil), .automatic)
        XCTAssertEqual(InterfaceSelection(persistedValue: "automatic"), .automatic)
        XCTAssertEqual(
            InterfaceSelection(persistedValue: "interface:utun3"),
            .named("utun3")
        )
        XCTAssertEqual(InterfaceSelection.named("en0").persistedValue, "interface:en0")
    }

    func testManualInterfaceSelectionDoesNotSilentlyFallBack() {
        let snapshot = NetworkInterfaceSnapshot(
            counters: ["en0": InterfaceByteCounters(received: 1, sent: 1)],
            interfaces: [NetworkInterfaceDescriptor(systemName: "en0", localizedName: "Wi-Fi")],
            primaryInterfaceName: "en0"
        )

        XCTAssertEqual(
            NetworkInterfaceProvider.selectedInterface(from: snapshot, selection: .automatic),
            "en0"
        )
        XCTAssertNil(
            NetworkInterfaceProvider.selectedInterface(
                from: snapshot,
                selection: .named("utun3")
            )
        )
    }

    func testMinuteAccumulatorUsesByteDeltasAndTracksPeaks() throws {
        let start = Date(timeIntervalSince1970: 10_800)
        var accumulator = MinuteTrafficAccumulator()

        XCTAssertNil(
            accumulator.consume(
                historySnapshot(
                    at: start.addingTimeInterval(1),
                    downloadRate: 100,
                    uploadRate: 40,
                    downloadBytes: 100,
                    uploadBytes: 40,
                    duration: 1
                )
            )
        )
        XCTAssertNil(
            accumulator.consume(
                historySnapshot(
                    at: start.addingTimeInterval(3),
                    downloadRate: 250,
                    uploadRate: 80,
                    downloadBytes: 500,
                    uploadBytes: 160,
                    duration: 2
                )
            )
        )

        let completed = try XCTUnwrap(
            accumulator.consume(
                NetworkSpeedSnapshot(
                    downloadBytesPerSecond: 0,
                    uploadBytesPerSecond: 0,
                    interfaceName: nil,
                    state: .unavailable,
                    sampledAt: start.addingTimeInterval(60)
                )
            )
        )

        XCTAssertEqual(completed.timestamp, start)
        XCTAssertEqual(completed.sampleCount, 2)
        XCTAssertEqual(completed.downloadBytes, 600)
        XCTAssertEqual(completed.uploadBytes, 200)
        XCTAssertEqual(completed.averageDownloadBytesPerSecond, 200, accuracy: 0.001)
        XCTAssertEqual(completed.averageUploadBytesPerSecond, 200.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(completed.peakDownloadBytesPerSecond, 250)
        XCTAssertEqual(completed.peakUploadBytesPerSecond, 80)
    }

    func testPartialMinuteRecordsMergeWithoutLosingEarlierSessionData() {
        let minute = Date(timeIntervalSince1970: 10_800)
        let first = TrafficMinuteRecord(
            timestamp: minute,
            averageDownloadBytesPerSecond: 100,
            averageUploadBytesPerSecond: 50,
            peakDownloadBytesPerSecond: 150,
            peakUploadBytesPerSecond: 60,
            sampleCount: 20,
            downloadBytes: 2_000,
            uploadBytes: 1_000
        )
        let second = TrafficMinuteRecord(
            timestamp: minute,
            averageDownloadBytesPerSecond: 300,
            averageUploadBytesPerSecond: 150,
            peakDownloadBytesPerSecond: 400,
            peakUploadBytesPerSecond: 180,
            sampleCount: 40,
            downloadBytes: 12_000,
            uploadBytes: 6_000
        )

        let merged = first.merging(second)

        XCTAssertEqual(merged.sampleCount, 60)
        XCTAssertEqual(merged.downloadBytes, 14_000)
        XCTAssertEqual(merged.uploadBytes, 7_000)
        XCTAssertEqual(merged.averageDownloadBytesPerSecond, 700.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(merged.averageUploadBytesPerSecond, 350.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(merged.peakDownloadBytesPerSecond, 400)
        XCTAssertEqual(merged.peakUploadBytesPerSecond, 180)
    }

    func testInvalidAndMissingSamplesDoNotCreateZeroHistory() {
        let start = Date(timeIntervalSince1970: 20_000)
        var accumulator = MinuteTrafficAccumulator()

        XCTAssertNil(
            accumulator.consume(
                NetworkSpeedSnapshot(
                    downloadBytesPerSecond: 0,
                    uploadBytesPerSecond: 0,
                    interfaceName: "en0",
                    state: .connected,
                    sampledAt: start,
                    isRateSampleValid: false
                )
            )
        )
        XCTAssertNil(
            accumulator.consume(
                NetworkSpeedSnapshot(
                    downloadBytesPerSecond: 0,
                    uploadBytesPerSecond: 0,
                    interfaceName: nil,
                    state: .unavailable,
                    sampledAt: start.addingTimeInterval(120)
                )
            )
        )
        XCTAssertNil(accumulator.finish())
    }

    func testResetAndInterfaceSwitchCannotProduceFalseSpike() {
        var calculator = SpeedSampleCalculator()
        _ = calculator.record(
            interfaceName: "en0",
            counters: InterfaceByteCounters(received: 1_000, sent: 1_000),
            uptimeNanoseconds: 1_000_000_000
        )
        calculator.reset()

        let afterWake = calculator.record(
            interfaceName: "en0",
            counters: InterfaceByteCounters(received: 9_000_000, sent: 8_000_000),
            uptimeNanoseconds: 9_000_000_000
        )
        let afterInterfaceSwitch = calculator.record(
            interfaceName: "utun4",
            counters: InterfaceByteCounters(received: 90_000_000, sent: 80_000_000),
            uptimeNanoseconds: 10_000_000_000
        )

        XCTAssertFalse(afterWake.isValid)
        XCTAssertFalse(afterInterfaceSwitch.isValid)
        XCTAssertEqual(afterWake.downloadBytesDelta, 0)
        XCTAssertEqual(afterInterfaceSwitch.downloadBytesDelta, 0)
    }

    func testDownsamplerPreservesGapsAndPointBudget() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let firstSegment = (0..<20).map {
            historyRecord(at: start.addingTimeInterval(TimeInterval($0 * 60)))
        }
        let secondStart = start.addingTimeInterval(40 * 60)
        let secondSegment = (0..<20).map {
            historyRecord(at: secondStart.addingTimeInterval(TimeInterval($0 * 60)))
        }

        let segments = TrafficHistoryDownsampler.segments(
            from: firstSegment + secondSegment,
            maximumPointCount: 12
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertLessThanOrEqual(segments.flatMap { $0 }.count, 12)
        XCTAssertGreaterThan(
            try XCTUnwrap(segments.last?.first?.timestamp).timeIntervalSince(
                try XCTUnwrap(segments.first?.last?.timestamp)
            ),
            90
        )
    }

    func testHistorySelectionFindsNearestRecordWithBinarySearch() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let records = (0..<4).map {
            historyRecord(at: start.addingTimeInterval(TimeInterval($0 * 60)))
        }

        XCTAssertEqual(
            TrafficHistorySelection.nearest(
                to: start.addingTimeInterval(-60),
                in: records
            ),
            records.first
        )
        XCTAssertEqual(
            TrafficHistorySelection.nearest(
                to: start.addingTimeInterval(95),
                in: records
            ),
            records[2]
        )
        XCTAssertEqual(
            TrafficHistorySelection.nearest(
                to: start.addingTimeInterval(10 * 60),
                in: records
            ),
            records.last
        )
        XCTAssertNil(TrafficHistorySelection.nearest(to: start, in: []))
    }

    func testHistoryDatabaseMigratesAnEmptyDatabase() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))

        let database = try TrafficHistoryDatabase(url: url)
        let version = try await database.schemaVersion()
        let records = try await database.records(since: .distantPast, through: .distantFuture)

        XCTAssertEqual(version, 1)
        XCTAssertTrue(records.isEmpty)
    }

    func testHistoryDatabaseQuarantinesCorruptFileAndRebuilds() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        try Data("not a sqlite database".utf8).write(to: url)

        let database = try TrafficHistoryDatabase(url: url)
        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ).filter { $0.hasPrefix("history.sqlite.corrupt-") }
        let version = try await database.schemaVersion()

        XCTAssertEqual(version, 1)
        XCTAssertEqual(quarantinedFiles.count, 1)
    }

    func testHistoryDatabasePrunesRecordsOlderThanSevenDays() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try TrafficHistoryDatabase(
            url: directory.appendingPathComponent("history.sqlite")
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expired = historyRecord(
            at: now.addingTimeInterval(-TrafficHistoryDatabase.retentionDuration - 60)
        )
        let retained = historyRecord(at: now.addingTimeInterval(-3_600))

        try await database.upsertAndPrune(expired, now: now)
        try await database.upsertAndPrune(retained, now: now)
        let records = try await database.records(
            since: now.addingTimeInterval(-8 * 24 * 60 * 60),
            through: now
        )

        XCTAssertEqual(records, [retained])
    }

    func testHistoryDatabaseMergesPartialWritesForTheSameMinute() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try TrafficHistoryDatabase(
            url: directory.appendingPathComponent("history.sqlite")
        )
        let minute = Date(timeIntervalSince1970: 1_800_000_000)
        let first = TrafficMinuteRecord(
            timestamp: minute,
            averageDownloadBytesPerSecond: 100,
            averageUploadBytesPerSecond: 50,
            peakDownloadBytesPerSecond: 120,
            peakUploadBytesPerSecond: 60,
            sampleCount: 20,
            downloadBytes: 2_000,
            uploadBytes: 1_000
        )
        let second = TrafficMinuteRecord(
            timestamp: minute,
            averageDownloadBytesPerSecond: 300,
            averageUploadBytesPerSecond: 150,
            peakDownloadBytesPerSecond: 450,
            peakUploadBytesPerSecond: 200,
            sampleCount: 40,
            downloadBytes: 12_000,
            uploadBytes: 6_000
        )

        try await database.upsertAndPrune(first, now: minute)
        try await database.upsertAndPrune(second, now: minute)
        let records = try await database.records(
            since: minute.addingTimeInterval(-1),
            through: minute.addingTimeInterval(1)
        )
        let merged = try XCTUnwrap(records.first)

        XCTAssertEqual(merged.sampleCount, 60)
        XCTAssertEqual(merged.downloadBytes, 14_000)
        XCTAssertEqual(merged.uploadBytes, 7_000)
        XCTAssertEqual(merged.averageDownloadBytesPerSecond, 700.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(merged.averageUploadBytesPerSecond, 350.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(merged.peakDownloadBytesPerSecond, 450)
        XCTAssertEqual(merged.peakUploadBytesPerSecond, 200)
    }

    @MainActor
    func testHistoryRangeChangesStatisticsImmediatelyFromSevenDayCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let database = try TrafficHistoryDatabase(url: url)
        let now = Date.now
        let recent = historyRecord(at: now.addingTimeInterval(-20 * 60))
        let older = TrafficMinuteRecord(
            timestamp: MinuteTrafficAccumulator.minuteStart(
                for: now.addingTimeInterval(-2 * 60 * 60)
            ),
            averageDownloadBytesPerSecond: 2_048,
            averageUploadBytesPerSecond: 1_024,
            peakDownloadBytesPerSecond: 4_096,
            peakUploadBytesPerSecond: 2_048,
            sampleCount: 60,
            downloadBytes: 122_880,
            uploadBytes: 61_440
        )
        try await database.upsertAndPrune(recent, now: now)
        try await database.upsertAndPrune(older, now: now)

        let store = TrafficHistoryStore(databaseURL: url)
        store.start(now: now)
        for _ in 0..<100 where store.isLoading {
            try await ContinuousClock().sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(store.isLoading)

        store.selectRange(.oneHour)
        XCTAssertEqual(store.summary.downloadBytes, recent.downloadBytes)

        store.selectRange(.sevenDays)
        XCTAssertEqual(
            store.summary.downloadBytes,
            recent.downloadBytes + older.downloadBytes
        )
        XCTAssertEqual(store.summary.peakDownloadBytesPerSecond, 4_096)
    }

    @MainActor
    func testPreferencesPersistAndDefaultToFullByteDisplay() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NetletTests.\(UUID())"))
        let store = PreferencesStore(defaults: defaults)

        XCTAssertEqual(store.menuDisplayStyle, .full)
        XCTAssertEqual(store.speedUnitMode, .bytes)
        XCTAssertEqual(store.interfaceSelection, .automatic)
        XCTAssertEqual(store.monitorConfiguration.refreshInterval, 1)

        store.setMenuDisplayStyle(.compact)
        store.setSpeedUnitMode(.bits)
        store.setDecimalPlaces(.two)
        store.setInterfaceSelection(.named("en7"))

        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.menuDisplayStyle, .compact)
        XCTAssertEqual(reloaded.speedUnitMode, .bits)
        XCTAssertEqual(reloaded.decimalPlaces, .two)
        XCTAssertEqual(reloaded.interfaceSelection, .named("en7"))
        XCTAssertEqual(reloaded.monitorConfiguration.refreshInterval, 1)
    }

    @MainActor
    func testDisplayUnitDoesNotChangeTheSamplingConfiguration() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NetletUnit.\(UUID())"))
        let store = PreferencesStore(defaults: defaults)
        let before = store.monitorConfiguration

        store.setSpeedUnitMode(.bits)

        XCTAssertEqual(store.monitorConfiguration, before)
    }

    @MainActor
    func testSimplifiedChineseIsTheDefaultLanguage() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NetletLanguage.\(UUID())"))
        let languageStore = LanguageStore(defaults: defaults)

        XCTAssertEqual(languageStore.language, .simplifiedChinese)
        XCTAssertEqual(languageStore[.download], "下载")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hans"])
    }

    private func historySnapshot(
        at date: Date,
        downloadRate: Double,
        uploadRate: Double,
        downloadBytes: UInt64,
        uploadBytes: UInt64,
        duration: TimeInterval
    ) -> NetworkSpeedSnapshot {
        NetworkSpeedSnapshot(
            downloadBytesPerSecond: downloadRate,
            uploadBytesPerSecond: uploadRate,
            interfaceName: "en0",
            state: .connected,
            sampledAt: date,
            isRateSampleValid: true,
            downloadBytesDelta: downloadBytes,
            uploadBytesDelta: uploadBytes,
            sampleDuration: duration
        )
    }

    private func historyRecord(at date: Date) -> TrafficMinuteRecord {
        TrafficMinuteRecord(
            timestamp: MinuteTrafficAccumulator.minuteStart(for: date),
            averageDownloadBytesPerSecond: 1_024,
            averageUploadBytesPerSecond: 512,
            peakDownloadBytesPerSecond: 2_048,
            peakUploadBytesPerSecond: 1_024,
            sampleCount: 60,
            downloadBytes: 61_440,
            uploadBytes: 30_720
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetletTests-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
