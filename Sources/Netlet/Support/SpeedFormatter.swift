import Foundation

enum SpeedFormatter {
    private static let fullUnitWidth = 4
    private static let compactUnitWidth = 2

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

    /// Produces a title whose character count stays constant for a given
    /// display style and decimal precision. The status item uses a monospaced
    /// font, so fixed value/unit slots keep both neighbouring menu bar items
    /// and the download/upload columns visually stationary.
    static func stableStatusTitle(
        snapshot: NetworkSpeedSnapshot,
        style: MenuDisplayStyle,
        unitMode: SpeedUnitMode,
        decimalPlaces: DecimalPlaces,
        scalePair: SpeedScalePair? = nil
    ) -> String {
        let compact = style == .compact
        let valueWidth = decimalPlaces.rawValue == 0
            ? 4
            : 5 + decimalPlaces.rawValue
        let unitWidth = compact ? compactUnitWidth : fullUnitWidth

        let download: (value: String, unit: String)
        let upload: (value: String, unit: String)
        if snapshot.state == .connected {
            download = valueAndUnit(
                bytesPerSecond: snapshot.downloadBytesPerSecond,
                unitMode: unitMode,
                decimalPlaces: decimalPlaces,
                compact: compact,
                scaleIndex: scalePair?.downloadIndex
            )
            upload = valueAndUnit(
                bytesPerSecond: snapshot.uploadBytesPerSecond,
                unitMode: unitMode,
                decimalPlaces: decimalPlaces,
                compact: compact,
                scaleIndex: scalePair?.uploadIndex
            )
        } else {
            download = ("—", "")
            upload = ("—", "")
        }

        let downloadText = stableDirectionText(
            arrow: "↓",
            value: download.value,
            unit: download.unit,
            valueWidth: valueWidth,
            unitWidth: unitWidth,
            compact: compact
        )
        let uploadText = stableDirectionText(
            arrow: "↑",
            value: upload.value,
            unit: upload.unit,
            valueWidth: valueWidth,
            unitWidth: unitWidth,
            compact: compact
        )

        switch style {
        case .full, .compact:
            return "\(downloadText)  \(uploadText)"
        case .downloadOnly:
            return downloadText
        case .uploadOnly:
            return uploadText
        }
    }

    static func dataSize(bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1_024, index < units.count - 1 {
            value /= 1_024
            index += 1
        }
        let decimals = index == 0 ? 0 : (value >= 100 ? 0 : 1)
        return "\(String(format: "%.*f", decimals, value)) \(units[index])"
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

    private static func stableDirectionText(
        arrow: String,
        value: String,
        unit: String,
        valueWidth: Int,
        unitWidth: Int,
        compact: Bool
    ) -> String {
        let paddedValue = leftPadding(value, to: valueWidth)
        let paddedUnit = rightPadding(unit, to: unitWidth)
        return compact
            ? "\(arrow)\(paddedValue)\(paddedUnit)"
            : "\(arrow) \(paddedValue) \(paddedUnit)"
    }

    private static func leftPadding(_ value: String, to width: Int) -> String {
        String(repeating: "\u{2007}", count: max(0, width - value.count)) + value
    }

    private static func rightPadding(_ value: String, to width: Int) -> String {
        value + String(repeating: "\u{2007}", count: max(0, width - value.count))
    }
}
