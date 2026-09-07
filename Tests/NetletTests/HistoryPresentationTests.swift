import Foundation
import Observation
import XCTest
@testable import Netlet

final class HistoryPresentationTests: XCTestCase {
    @MainActor
    func testHiddenHistoryDoesNotPublishButStillCollectsEverySample() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TrafficHistoryStore(databaseURL: url)
        let start = MinuteTrafficAccumulator.minuteStart(for: .now).addingTimeInterval(1)
        store.setPresentationActive(true, for: .menu, now: start)
        store.setPresentationActive(false, for: .menu)
        for second in 1...10 { store.ingest(sample(at: start.addingTimeInterval(Double(second)))) }
        XCTAssertEqual(store.presentationDate, start)
        XCTAssertEqual(store.liveRecord?.downloadBytes, 1_000)
        store.setPresentationActive(true, for: .menu, now: start.addingTimeInterval(11))
        XCTAssertEqual(store.presentationRecords(for: .oneHour).last?.downloadBytes, 1_000)
    }

    @MainActor
    func testVisibleHistoryThrottlesAndKeepsIndependentConsumers() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TrafficHistoryStore(databaseURL: url)
        let start = MinuteTrafficAccumulator.minuteStart(for: .now).addingTimeInterval(1)
        store.setPresentationActive(true, for: .menu, now: start)
        store.setPresentationActive(true, for: .settings, now: start)
        store.setPresentationActive(false, for: .menu)
        for second in 1...4 { store.ingest(sample(at: start.addingTimeInterval(Double(second)))) }
        XCTAssertEqual(store.presentationDate, start)
        store.ingest(sample(at: start.addingTimeInterval(5)))
        XCTAssertEqual(store.presentationDate, start.addingTimeInterval(5))
        XCTAssertEqual(store.presentationRecords(for: .oneHour).last?.downloadBytes, 500)
        store.setPresentationActive(false, for: .settings)
        store.ingest(sample(at: start.addingTimeInterval(12)))
        XCTAssertEqual(store.presentationDate, start.addingTimeInterval(5))
    }

    @MainActor
    func testPresentationCacheInvalidatesOnRefreshAndClear() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TrafficHistoryStore(databaseURL: url)
        let start = MinuteTrafficAccumulator.minuteStart(for: .now).addingTimeInterval(1)
        store.setPresentationActive(true, for: .menu, now: start)
        XCTAssertTrue(store.presentationSegments(for: .oneHour, maximumPointCount: 120).isEmpty)
        store.ingest(sample(at: start.addingTimeInterval(5)))
        XCTAssertFalse(store.presentationSegments(for: .oneHour, maximumPointCount: 120).isEmpty)
        store.clearHistory()
        XCTAssertTrue(store.presentationSegments(for: .oneHour, maximumPointCount: 120).isEmpty)
        XCTAssertEqual(store.summary.downloadBytes, 0)
    }

    private func sample(at date: Date) -> NetworkSpeedSnapshot {
        NetworkSpeedSnapshot(downloadBytesPerSecond: 100, uploadBytesPerSecond: 50,
            interfaceName: "en0", state: .connected, sampledAt: date,
            isRateSampleValid: true, downloadBytesDelta: 100, uploadBytesDelta: 50,
            sampleDuration: 1)
    }
}
