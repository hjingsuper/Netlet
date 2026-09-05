import Foundation

enum SpeedFormatter {
    static func valueAndUnit(
        bytesPerSecond: Double,
        unitMode: SpeedUnitMode,
        decimalPlaces: DecimalPlaces,
        compact: Bool = false,
        scaleIndex: Int? = nil
    ) -> (value: String, unit: String) {
        let safeRate = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        let scaled: Double
        let unit: String

        switch unitMode {
        case .bytes:
            (scaled, unit) = scale(
                value: safeRate,
                base: 1_024,
                units: compact ? ["B", "K", "M", "G"] : ["B/s", "KB/s", "MB/s", "GB/s"],
                scaleIndex: scaleIndex
            )
        case .bits:
            (scaled, unit) = scale(
                value: safeRate * 8,
                base: 1_000,
                units: compact ? ["b", "Kb", "Mb", "Gb"] : ["bps", "Kbps", "Mbps", "Gbps"],
                scaleIndex: scaleIndex
            )
        }

        return (
            String(format: "%.*f", decimalPlaces.rawValue, scaled),
            unit
        )
    }

    static func statusTitle(
        snapshot: NetworkSpeedSnapshot,
        style: MenuDisplayStyle,
        unitMode: SpeedUnitMode,
        decimalPlaces: DecimalPlaces,
        scalePair: SpeedScalePair? = nil
    ) -> String {
        guard snapshot.state == .connected else {
            switch style {
            case .full, .compact: return "↓ —  ↑ —"
            case .downloadOnly: return "↓ —"
            case .uploadOnly: return "↑ —"
            }
        }

        let compact = style == .compact
        let download = valueAndUnit(
            bytesPerSecond: snapshot.downloadBytesPerSecond,
            unitMode: unitMode,
            decimalPlaces: decimalPlaces,
            compact: compact,
            scaleIndex: scalePair?.downloadIndex
        )
        let upload = valueAndUnit(
            bytesPerSecond: snapshot.uploadBytesPerSecond,
            unitMode: unitMode,
            decimalPlaces: decimalPlaces,
            compact: compact,
            scaleIndex: scalePair?.uploadIndex
        )
        let downloadText = compact
            ? "↓\(download.value)\(download.unit)"
            : "↓ \(download.value) \(download.unit)"
        let uploadText = compact
            ? "↑\(upload.value)\(upload.unit)"
            : "↑ \(upload.value) \(upload.unit)"

        switch style {
        case .full, .compact:
            return "\(downloadText)  \(uploadText)"
        case .downloadOnly:
            return downloadText
        case .uploadOnly:
            return uploadText
        }
    }

    private static func scale(
        value: Double,
        base: Double,
        units: [String],
        scaleIndex: Int?
    ) -> (Double, String) {
        var scaled = value
        let index: Int

        if let scaleIndex {
            index = max(0, min(scaleIndex, units.count - 1))
            for _ in 0..<index {
                scaled /= base
            }
        } else {
            var automaticIndex = 0
            while scaled >= base, automaticIndex < units.count - 1 {
                scaled /= base
                automaticIndex += 1
            }
            index = automaticIndex
        }
        return (scaled, units[index])
    }
}
