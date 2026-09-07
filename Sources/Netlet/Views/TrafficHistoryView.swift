import Charts
import SwiftUI

struct TrafficHistoryView: View {
    let historyStore: TrafficHistoryStore
    let preferences: PreferencesStore
    let languageStore: LanguageStore

    @State private var isClearConfirmationPresented = false
    @State private var hoveredRecord: TrafficMinuteRecord?

    var body: some View {
        VStack(spacing: 10) {
            header
            summary
            chart
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
        .confirmationDialog(
            languageStore[.clearHistory],
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(languageStore[.confirmClear], role: .destructive) {
                historyStore.clearHistory()
            }
            Button(languageStore[.cancel], role: .cancel) {}
        } message: {
            Text(languageStore[.clearHistoryConfirmation])
        }
        .onChange(of: historyStore.selectedRange) { _, _ in
            hoveredRecord = nil
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(languageStore[.history])
                    .font(.headline)
                Text(historyCoverageDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            legend
            Spacer(minLength: 12)

            Picker("", selection: rangeBinding) {
                Text(languageStore[.oneHour]).tag(TrafficHistoryRange.oneHour)
                Text(languageStore[.twentyFourHours]).tag(TrafficHistoryRange.twentyFourHours)
                Text(languageStore[.sevenDays]).tag(TrafficHistoryRange.sevenDays)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 250)

            Button(role: .destructive) {
                isClearConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(languageStore[.clearHistory])
            .disabled(historyStore.visibleRecords.isEmpty)
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(color: .blue, title: languageStore[.download])
            legendItem(color: .green, title: languageStore[.upload])
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
        }
    }

    private var summary: some View {
        let values = historyStore.summary

        return HStack(spacing: 0) {
            summaryMetric(
                title: languageStore[.totalDownload],
                value: SpeedFormatter.dataSize(bytes: values.downloadBytes),
                color: .blue
            )
            metricDivider
            summaryMetric(
                title: languageStore[.totalUpload],
                value: SpeedFormatter.dataSize(bytes: values.uploadBytes),
                color: .green
            )
            metricDivider
            summaryMetric(
                title: languageStore[.peakDownload],
                value: formattedSpeed(values.peakDownloadBytesPerSecond),
                color: .blue
            )
            metricDivider
            summaryMetric(
                title: languageStore[.peakUpload],
                value: formattedSpeed(values.peakUploadBytesPerSecond),
                color: .green
            )
        }
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }

    private func summaryMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.18), value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 30)
    }

    private var chart: some View {
        GeometryReader { geometry in
            let records = historyStore.visibleRecords
            let pointBudget = max(60, min(600, Int(geometry.size.width / 2.5)))
            let segments = historyStore.presentationSegments(
                for: historyStore.selectedRange,
                maximumPointCount: pointBudget
            )

            ZStack {
                if historyStore.isAvailable, !records.isEmpty {
                    historyChart(segments: segments)
                } else {
                    ContentUnavailableView {
                        Label(
                            historyStore.isAvailable
                                ? languageStore[.noHistoryData]
                                : languageStore[.historyUnavailable],
                            systemImage: historyStore.isAvailable ? "chart.xyaxis.line" : "exclamationmark.triangle"
                        )
                    }
                    .controlSize(.small)
                }

                if historyStore.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(height: 132)
    }

    private func historyChart(segments: [[TrafficMinuteRecord]]) -> some View {
        let now = historyStore.presentationDate
        let start = now.addingTimeInterval(-historyStore.selectedRange.duration)
        let maximum = max(
            1,
            historyStore.visibleRecords.reduce(0) {
                max(
                    $0,
                    $1.averageDownloadBytesPerSecond,
                    $1.averageUploadBytesPerSecond
                )
            }
        )

        return Chart {
            ForEach(Array(segments.enumerated()), id: \.offset) { segmentIndex, segment in
                ForEach(segment) { record in
                    AreaMark(
                        x: .value("Time", record.timestamp),
                        yStart: .value("Download baseline", 0),
                        yEnd: .value("Download area", record.averageDownloadBytesPerSecond),
                        series: .value("Download area segment", "download-area-\(segmentIndex)")
                    )
                    .foregroundStyle(Color.blue.opacity(0.08))

                    AreaMark(
                        x: .value("Time", record.timestamp),
                        yStart: .value("Upload baseline", 0),
                        yEnd: .value("Upload area", record.averageUploadBytesPerSecond),
                        series: .value("Upload area segment", "upload-area-\(segmentIndex)")
                    )
                    .foregroundStyle(Color.green.opacity(0.08))

                    LineMark(
                        x: .value("Time", record.timestamp),
                        y: .value("Download", record.averageDownloadBytesPerSecond),
                        series: .value("Download segment", "download-\(segmentIndex)")
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                    LineMark(
                        x: .value("Time", record.timestamp),
                        y: .value("Upload", record.averageUploadBytesPerSecond),
                        series: .value("Upload segment", "upload-\(segmentIndex)")
                    )
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }

                if let onlyRecord = segment.count == 1 ? segment.first : nil {
                    PointMark(
                        x: .value("Time", onlyRecord.timestamp),
                        y: .value("Download", onlyRecord.averageDownloadBytesPerSecond)
                    )
                    .foregroundStyle(Color.blue)
                    PointMark(
                        x: .value("Time", onlyRecord.timestamp),
                        y: .value("Upload", onlyRecord.averageUploadBytesPerSecond)
                    )
                    .foregroundStyle(Color.green)
                }
            }

            if let latest = segments.last?.last {
                PointMark(
                    x: .value("Time", latest.timestamp),
                    y: .value("Download", latest.averageDownloadBytesPerSecond)
                )
                .foregroundStyle(Color.blue)
                .symbolSize(24)

                PointMark(
                    x: .value("Time", latest.timestamp),
                    y: .value("Upload", latest.averageUploadBytesPerSecond)
                )
                .foregroundStyle(Color.green)
                .symbolSize(24)
            }

            if let hoveredRecord {
                RuleMark(x: .value("Selected time", hoveredRecord.timestamp))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        spacing: 6,
                        overflowResolution: AnnotationOverflowResolution(
                            x: .fit(to: .chart),
                            y: .fit(to: .chart)
                        )
                    ) {
                        historyTooltip(for: hoveredRecord)
                            .allowsHitTesting(false)
                    }

                PointMark(
                    x: .value("Selected time", hoveredRecord.timestamp),
                    y: .value("Selected download", hoveredRecord.averageDownloadBytesPerSecond)
                )
                .foregroundStyle(Color.blue)
                .symbolSize(52)

                PointMark(
                    x: .value("Selected time", hoveredRecord.timestamp),
                    y: .value("Selected upload", hoveredRecord.averageUploadBytesPerSecond)
                )
                .foregroundStyle(Color.green)
                .symbolSize(52)
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: start...now)
        .chartYScale(domain: 0...(maximum * 1.08))
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 6)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.separator.opacity(0.55))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisDateLabel(date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.separator.opacity(0.55))
                AxisValueLabel {
                    if let speed = value.as(Double.self) {
                        Text(axisSpeedLabel(speed))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            guard
                                let plotFrameAnchor = proxy.plotFrame,
                                geometry[plotFrameAnchor].contains(location)
                            else {
                                setHoveredRecord(nil)
                                return
                            }

                            let plotFrame = geometry[plotFrameAnchor]
                            let plotX = location.x - plotFrame.origin.x
                            guard let date: Date = proxy.value(atX: plotX) else {
                                setHoveredRecord(nil)
                                return
                            }
                            setHoveredRecord(
                                TrafficHistorySelection.nearest(
                                    to: date,
                                    in: historyStore.visibleRecords
                                )
                            )
                        case .ended:
                            setHoveredRecord(nil)
                        }
                    }
            }
        }
    }

    private func historyTooltip(for record: TrafficMinuteRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hoverDateLabel(record.timestamp))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text("↓ \(formattedSpeed(record.averageDownloadBytesPerSecond))")
                    .foregroundStyle(Color.blue)
                Text("↑ \(formattedSpeed(record.averageUploadBytesPerSecond))")
                    .foregroundStyle(Color.green)
            }
            .monospacedDigit()
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private func setHoveredRecord(_ record: TrafficMinuteRecord?) {
        guard hoveredRecord?.timestamp != record?.timestamp else { return }
        hoveredRecord = record
    }

    private func formattedSpeed(_ bytesPerSecond: Double) -> String {
        let value = SpeedFormatter.valueAndUnit(
            bytesPerSecond: bytesPerSecond,
            unitMode: preferences.speedUnitMode,
            decimalPlaces: preferences.decimalPlaces
        )
        return "\(value.value) \(value.unit)"
    }

    private func axisSpeedLabel(_ bytesPerSecond: Double) -> String {
        let value = SpeedFormatter.valueAndUnit(
            bytesPerSecond: bytesPerSecond,
            unitMode: preferences.speedUnitMode,
            decimalPlaces: .one,
            compact: true
        )
        return "\(value.value)\(value.unit)"
    }

    private func axisDateLabel(_ date: Date) -> String {
        let format: Date.FormatStyle
        switch historyStore.selectedRange {
        case .oneHour:
            format = .dateTime.hour().minute()
        case .twentyFourHours:
            format = .dateTime.hour()
        case .sevenDays:
            format = .dateTime.month(.twoDigits).day(.twoDigits)
        }
        return date.formatted(format.locale(languageStore.language.locale))
    }

    private func hoverDateLabel(_ date: Date) -> String {
        let format: Date.FormatStyle = historyStore.selectedRange == .sevenDays
            ? .dateTime.month(.twoDigits).day(.twoDigits).hour().minute()
            : .dateTime.hour().minute()
        return date.formatted(format.locale(languageStore.language.locale))
    }

    private var rangeBinding: Binding<TrafficHistoryRange> {
        Binding(
            get: { historyStore.selectedRange },
            set: { historyStore.selectRange($0) }
        )
    }

    private var historyCoverageDescription: String {
        guard
            let firstTimestamp = historyStore
                .presentationRecords(for: .sevenDays)
                .first?
                .timestamp
        else {
            return languageStore[.historyRetentionDescription]
        }

        let duration = max(60, historyStore.presentationDate.timeIntervalSince(firstTimestamp))
        let value: Int
        let simplifiedChineseUnit: String
        let englishUnit: String

        if duration < 60 * 60 {
            value = max(1, Int(duration / 60))
            simplifiedChineseUnit = "分钟"
            englishUnit = value == 1 ? "minute" : "minutes"
        } else if duration < 24 * 60 * 60 {
            value = max(1, Int(duration / (60 * 60)))
            simplifiedChineseUnit = "小时"
            englishUnit = value == 1 ? "hour" : "hours"
        } else {
            value = max(1, Int(duration / (24 * 60 * 60)))
            simplifiedChineseUnit = "天"
            englishUnit = value == 1 ? "day" : "days"
        }

        switch languageStore.language {
        case .simplifiedChinese:
            return "数据跨度 \(value) \(simplifiedChineseUnit) · 仅保留最近 7 天"
        case .english:
            return "\(value) \(englishUnit) of data · Last 7 days only"
        }
    }
}

private extension AppLanguage {
    var locale: Locale {
        Locale(identifier: rawValue)
    }
}
