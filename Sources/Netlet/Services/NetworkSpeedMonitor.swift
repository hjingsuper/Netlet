import AppKit
import Foundation
import Observation

private final class NetworkPollEngine: @unchecked Sendable {
    typealias Update = @Sendable (
        NetworkSpeedSnapshot,
        [NetworkInterfaceDescriptor]
    ) -> Void

    init(queue: DispatchQueue = DispatchQueue(label: "com.hjingsuper.Netlet.network", qos: .utility)) {
        self.queue = queue
    }

    func start(configuration: NetworkMonitorConfiguration, update: @escaping Update) {
        queue.async { [weak self] in
            guard let self else { return }
            stopLocked()
            calculator.reset()
            self.update = update
            self.configuration = configuration

            let source = DispatchSource.makeTimerSource(queue: queue)
            let leeway = max(0.05, min(configuration.refreshInterval * 0.15, 0.25))
            source.schedule(
                deadline: .now(),
                repeating: configuration.refreshInterval,
                leeway: .milliseconds(Int(leeway * 1_000))
            )
            source.setEventHandler { [weak self] in
                self?.poll()
            }
            timer = source
            source.resume()
        }
    }

    func resetBaseline() {
        queue.async { [weak self] in
            self?.calculator.reset()
        }
    }

    func stop() {
        queue.sync {
            stopLocked()
        }
    }

    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var calculator = SpeedSampleCalculator()
    private var configuration = NetworkMonitorConfiguration(
        interfaceSelection: .automatic
    )
    private var update: Update?

    private func poll() {
        let interfaceSnapshot = NetworkInterfaceProvider.snapshot()
        let interfaceName = NetworkInterfaceProvider.selectedInterface(
            from: interfaceSnapshot,
            selection: configuration.interfaceSelection
        )

        guard
            let interfaceName,
            let counters = interfaceSnapshot.counters[interfaceName]
        else {
            calculator.reset()
            update?(
                NetworkSpeedSnapshot(
                    downloadBytesPerSecond: 0,
                    uploadBytesPerSecond: 0,
                    interfaceName: nil,
                    state: .unavailable,
                    sampledAt: .now
                ),
                interfaceSnapshot.interfaces
            )
            return
        }

        let rates = calculator.record(
            interfaceName: interfaceName,
            counters: counters,
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        update?(
            NetworkSpeedSnapshot(
                downloadBytesPerSecond: rates.download,
                uploadBytesPerSecond: rates.upload,
                interfaceName: interfaceName,
                state: .connected,
                sampledAt: .now
            ),
            interfaceSnapshot.interfaces
        )
    }

    private func stopLocked() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        update = nil
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

@MainActor
@Observable
final class NetworkSpeedMonitor: NSObject {
    private(set) var snapshot = NetworkSpeedSnapshot.initial
    private(set) var availableInterfaces: [NetworkInterfaceDescriptor] = []
    private(set) var byteScalePair = SpeedScalePair()
    private(set) var bitScalePair = SpeedScalePair()
    var onUpdate: (() -> Void)?

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspacePowerStateDidChange),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspacePowerStateDidChange),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func start(configuration: NetworkMonitorConfiguration) {
        self.configuration = configuration
        generation &+= 1
        let expectedGeneration = generation
        engine.start(configuration: configuration) { [weak self] snapshot, interfaces in
            Task { @MainActor [weak self] in
                guard let self, self.generation == expectedGeneration else { return }
                self.updateDisplayScales(for: snapshot)
                self.snapshot = snapshot
                self.availableInterfaces = interfaces
                self.onUpdate?()
            }
        }
    }

    func reconfigure(_ configuration: NetworkMonitorConfiguration) {
        self.configuration = configuration
        start(configuration: configuration)
    }

    func resetBaseline() {
        engine.resetBaseline()
    }

    func scalePair(for unitMode: SpeedUnitMode) -> SpeedScalePair {
        switch unitMode {
        case .bytes: byteScalePair
        case .bits: bitScalePair
        }
    }

    private let engine = NetworkPollEngine()
    private var generation: UInt64 = 0
    private var byteDownloadScale = SpeedScaleHysteresis()
    private var byteUploadScale = SpeedScaleHysteresis()
    private var bitDownloadScale = SpeedScaleHysteresis()
    private var bitUploadScale = SpeedScaleHysteresis()
    private var configuration = NetworkMonitorConfiguration(
        interfaceSelection: .automatic
    )

    private func updateDisplayScales(for newSnapshot: NetworkSpeedSnapshot) {
        if newSnapshot.state != .connected || newSnapshot.interfaceName != snapshot.interfaceName {
            resetDisplayScales()
        }

        guard newSnapshot.state == .connected else { return }

        byteScalePair = SpeedScalePair(
            downloadIndex: byteDownloadScale.update(
                value: newSnapshot.downloadBytesPerSecond,
                base: 1_024,
                maximumIndex: 3
            ),
            uploadIndex: byteUploadScale.update(
                value: newSnapshot.uploadBytesPerSecond,
                base: 1_024,
                maximumIndex: 3
            )
        )
        bitScalePair = SpeedScalePair(
            downloadIndex: bitDownloadScale.update(
                value: newSnapshot.downloadBytesPerSecond * 8,
                base: 1_000,
                maximumIndex: 3
            ),
            uploadIndex: bitUploadScale.update(
                value: newSnapshot.uploadBytesPerSecond * 8,
                base: 1_000,
                maximumIndex: 3
            )
        )
    }

    private func resetDisplayScales() {
        byteDownloadScale.reset()
        byteUploadScale.reset()
        bitDownloadScale.reset()
        bitUploadScale.reset()
        byteScalePair = SpeedScalePair()
        bitScalePair = SpeedScalePair()
    }

    @objc private func workspacePowerStateDidChange() {
        resetBaseline()
    }

    deinit {
        engine.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
