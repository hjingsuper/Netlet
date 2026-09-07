import Charts
import SwiftUI

struct SpeedMenuView: View {
    static let preferredWidth: CGFloat = 320
    static let preferredHeight: CGFloat = 150

    let monitor: NetworkSpeedMonitor
    let preferences: PreferencesStore
    let historyStore: TrafficHistoryStore
    let languageStore: LanguageStore

    var body: some View {
        let scalePair = monitor.scalePair(for: preferences.speedUnitMode)

        VStack(spacing: 7) {
            HStack(spacing: 8) {
                speedColumn(
                    arrow: "↓",
                    label: languageStore[.download],
                    bytesPerSecond: monitor.snapshot.downloadBytesPerSecond,
                    scaleIndex: scalePair.downloadIndex,
                    color: .blue
                )

                Divider()
                    .frame(height: 44)

                speedColumn(
                    arrow: "↑",
                    label: languageStore[.upload],
                    bytesPerSecond: monitor.snapshot.uploadBytesPerSecond,
                    scaleIndex: scalePair.uploadIndex,
                    color: .mint
                )
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)

                Text(connectionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Divider()

            MenuHistoryView(historyStore: historyStore, languageStore: languageStore)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: Self.preferredWidth, height: Self.preferredHeight)
    }

    private func speedColumn(
        arrow: String,
        label: String,
        bytesPerSecond: Double,
        scaleIndex: Int,
        color: Color
    ) -> some View {
        let formatted = SpeedFormatter.valueAndUnit(
            bytesPerSecond: bytesPerSecond,
            unitMode: preferences.speedUnitMode,
            decimalPlaces: preferences.decimalPlaces,
            scaleIndex: scaleIndex
        )

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(arrow)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(speedValue(formatted.value))
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                if monitor.snapshot.state == .connected {
                    Text(formatted.unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionDescription: String {
        guard let interfaceName = monitor.snapshot.interfaceName else {
            return languageStore[.networkUnavailable]
        }
        let name = monitor.availableInterfaces
            .first { $0.systemName == interfaceName }?.localizedName ?? interfaceName
        return "\(languageStore[.currentConnection]) · \(name) (\(interfaceName))"
    }

    private var connectionColor: Color {
        switch monitor.snapshot.state {
        case .connected: .green
        case .unavailable: .secondary
        }
    }

    private func speedValue(_ connectedValue: String) -> String {
        switch monitor.snapshot.state {
        case .connected: connectedValue
        case .unavailable: "—"
        }
    }
}

// A separate View creates a dependency boundary: live speed cannot invalidate the chart.
private struct MenuHistoryView: View {
    let historyStore: TrafficHistoryStore
    let languageStore: LanguageStore
    var body: some View {
        let records = historyStore.presentationRecords(for: .oneHour)
        let segments = historyStore.presentationSegments(
            for: .oneHour,
            maximumPointCount: 120
        )
        let maximum = max(
            1,
            records.reduce(0) {
                max(
                    $0,
                    $1.averageDownloadBytesPerSecond,
                    $1.averageUploadBytesPerSecond
                )
            }
        )

        return VStack(spacing: 3) {
            HStack(spacing: 8) {
                Text(languageStore[.lastHourTrend])
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                historyLegend(color: .blue, title: languageStore[.download])
                historyLegend(color: .green, title: languageStore[.upload])
            }

            if records.isEmpty {
                Text(languageStore[.noHistoryData])
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 31)
            } else {
                Chart {
                    ForEach(Array(segments.enumerated()), id: \.offset) { segmentIndex, segment in
                        ForEach(segment) { record in
                            LineMark(
                                x: .value("Time", record.timestamp),
                                y: .value("Download", record.averageDownloadBytesPerSecond),
                                series: .value("Download segment", "download-\(segmentIndex)")
                            )
                            .foregroundStyle(Color.blue)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                            LineMark(
                                x: .value("Time", record.timestamp),
                                y: .value("Upload", record.averageUploadBytesPerSecond),
                                series: .value("Upload segment", "upload-\(segmentIndex)")
                            )
                            .foregroundStyle(Color.green)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        }

                        if let onlyRecord = segment.count == 1 ? segment.first : nil {
                            PointMark(
                                x: .value("Time", onlyRecord.timestamp),
                                y: .value("Download", onlyRecord.averageDownloadBytesPerSecond)
                            )
                            .foregroundStyle(Color.blue)
                            .symbolSize(12)
                            PointMark(
                                x: .value("Time", onlyRecord.timestamp),
                                y: .value("Upload", onlyRecord.averageUploadBytesPerSecond)
                            )
                            .foregroundStyle(Color.green)
                            .symbolSize(12)
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartXScale(
                    domain: historyStore.presentationDate.addingTimeInterval(-TrafficHistoryRange.oneHour.duration)...historyStore.presentationDate
                )
                .chartYScale(domain: 0...(maximum * 1.08))
                .frame(height: 31)
            }
        }
    }

    private func historyLegend(color: Color, title: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(title)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

}
