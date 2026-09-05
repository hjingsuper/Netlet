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
}
