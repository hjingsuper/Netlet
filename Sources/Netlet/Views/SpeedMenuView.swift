import SwiftUI

struct SpeedMenuView: View {
    static let preferredWidth: CGFloat = 320
    static let preferredHeight: CGFloat = 92

    let monitor: NetworkSpeedMonitor
    let preferences: PreferencesStore
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
