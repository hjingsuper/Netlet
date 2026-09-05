import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
}

enum L10nKey {
    case appSubtitle
    case automatic
    case automaticUpdatesDescription
    case bits
    case bytes
    case checkForUpdates
    case compact
    case currentConnection
    case decimalPlaces
    case disclaimer
    case download
    case downloadOnly
    case english
    case full
    case github
    case history
    case historyUnavailable
    case historyRetentionDescription
    case interface
    case interfaceUnavailable
    case language
    case launchAtLogin
    case launchAtLoginFailed
    case launchAtLoginNeedsApproval
    case launchAtLoginUnavailable
    case lastHourTrend
    case menuBarDisplay
    case networkUnavailable
    case noHistoryData
    case openLoginItems
    case preferences
    case quit
    case retry
    case simplifiedChinese
    case speedUnit
    case oneHour
    case twentyFourHours
    case sevenDays
    case totalDownload
    case totalUpload
    case peakDownload
    case peakUpload
    case clearHistory
    case clearHistoryConfirmation
    case cancel
    case confirmClear
    case upload
    case uploadOnly
}

@MainActor
@Observable
final class LanguageStore {
    private enum Keys {
        static let language = "netlet.language"
        static let appleLanguages = "AppleLanguages"
    }

    private(set) var language: AppLanguage
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: Keys.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese
        synchronizeBundleLanguage()
    }

    func setLanguage(_ value: AppLanguage) {
        guard value != language else { return }
        language = value
        defaults.set(value.rawValue, forKey: Keys.language)
        synchronizeBundleLanguage()
        onChange?()
    }

    subscript(_ key: L10nKey) -> String {
        switch (language, key) {
        case (.simplifiedChinese, .appSubtitle): "菜单栏实时网速"
        case (.simplifiedChinese, .automatic): "自动"
        case (.simplifiedChinese, .automaticUpdatesDescription): "自动在后台下载更新，安装完成后重新启动。"
        case (.simplifiedChinese, .bits): "比特/秒（bit/s）"
        case (.simplifiedChinese, .bytes): "字节/秒（B/s）"
        case (.simplifiedChinese, .checkForUpdates): "检查更新…"
        case (.simplifiedChinese, .compact): "紧凑"
        case (.simplifiedChinese, .currentConnection): "当前连接"
        case (.simplifiedChinese, .decimalPlaces): "小数位"
        case (.simplifiedChinese, .disclaimer): "本软件为免费开源项目，仅供交流学习与个人使用。请遵守相关法律法规与开源协议，勿用于任何商业或非法用途。"
        case (.simplifiedChinese, .download): "下载"
        case (.simplifiedChinese, .downloadOnly): "仅下载"
        case (.simplifiedChinese, .english): "English"
        case (.simplifiedChinese, .full): "完整"
        case (.simplifiedChinese, .github): "在 GitHub 查看源码"
        case (.simplifiedChinese, .history): "流量历史"
        case (.simplifiedChinese, .historyUnavailable): "历史记录暂不可用"
        case (.simplifiedChinese, .historyRetentionDescription): "仅保留最近 7 天"
        case (.simplifiedChinese, .interface): "网络接口"
        case (.simplifiedChinese, .interfaceUnavailable): "当前不可用"
        case (.simplifiedChinese, .language): "语言"
        case (.simplifiedChinese, .launchAtLogin): "开机自启"
        case (.simplifiedChinese, .launchAtLoginFailed): "注册失败，请确认应用位于“应用程序”文件夹。"
        case (.simplifiedChinese, .launchAtLoginNeedsApproval): "需要在系统设置中允许登录项。"
        case (.simplifiedChinese, .launchAtLoginUnavailable): "请先将 Netlet 安装到“应用程序”。"
        case (.simplifiedChinese, .lastHourTrend): "近 1 小时"
        case (.simplifiedChinese, .menuBarDisplay): "菜单栏显示"
        case (.simplifiedChinese, .networkUnavailable): "暂无可用网络"
        case (.simplifiedChinese, .noHistoryData): "该时段暂无数据"
        case (.simplifiedChinese, .openLoginItems): "打开登录项设置"
        case (.simplifiedChinese, .preferences): "偏好设置…"
        case (.simplifiedChinese, .quit): "退出 Netlet"
        case (.simplifiedChinese, .retry): "重新检测"
        case (.simplifiedChinese, .simplifiedChinese): "简体中文"
        case (.simplifiedChinese, .speedUnit): "速度单位"
        case (.simplifiedChinese, .oneHour): "1 小时"
        case (.simplifiedChinese, .twentyFourHours): "24 小时"
        case (.simplifiedChinese, .sevenDays): "7 天"
        case (.simplifiedChinese, .totalDownload): "下载总量"
        case (.simplifiedChinese, .totalUpload): "上传总量"
        case (.simplifiedChinese, .peakDownload): "下载峰值"
        case (.simplifiedChinese, .peakUpload): "上传峰值"
        case (.simplifiedChinese, .clearHistory): "清除历史"
        case (.simplifiedChinese, .clearHistoryConfirmation): "将永久清除本机保存的全部流量历史。此操作不会更改其他偏好设置。"
        case (.simplifiedChinese, .cancel): "取消"
        case (.simplifiedChinese, .confirmClear): "清除"
        case (.simplifiedChinese, .upload): "上传"
        case (.simplifiedChinese, .uploadOnly): "仅上传"

        case (.english, .appSubtitle): "Live network speed in your menu bar"
        case (.english, .automatic): "Automatic"
        case (.english, .automaticUpdatesDescription): "Downloads updates in the background, installs them, then relaunches."
        case (.english, .bits): "Bits/second (bit/s)"
        case (.english, .bytes): "Bytes/second (B/s)"
        case (.english, .checkForUpdates): "Check for Updates…"
        case (.english, .compact): "Compact"
        case (.english, .currentConnection): "Current Connection"
        case (.english, .decimalPlaces): "Decimal Places"
        case (.english, .disclaimer): "Netlet is a free, open-source project for learning and personal use only. Follow applicable laws and open-source licenses; do not use it commercially or illegally."
        case (.english, .download): "Download"
        case (.english, .downloadOnly): "Download Only"
        case (.english, .english): "English"
        case (.english, .full): "Full"
        case (.english, .github): "View Source on GitHub"
        case (.english, .history): "Traffic History"
        case (.english, .historyUnavailable): "History is temporarily unavailable"
        case (.english, .historyRetentionDescription): "Last 7 days only"
        case (.english, .interface): "Network Interface"
        case (.english, .interfaceUnavailable): "Currently Unavailable"
        case (.english, .language): "Language"
        case (.english, .launchAtLogin): "Launch at Login"
        case (.english, .launchAtLoginFailed): "Registration failed. Make sure Netlet is in Applications."
        case (.english, .launchAtLoginNeedsApproval): "Allow the login item in System Settings."
        case (.english, .launchAtLoginUnavailable): "Install Netlet in Applications first."
        case (.english, .lastHourTrend): "Last Hour"
        case (.english, .menuBarDisplay): "Menu Bar Display"
        case (.english, .networkUnavailable): "No network available"
        case (.english, .noHistoryData): "No data for this range"
        case (.english, .openLoginItems): "Open Login Items"
        case (.english, .preferences): "Settings…"
        case (.english, .quit): "Quit Netlet"
        case (.english, .retry): "Retry"
        case (.english, .simplifiedChinese): "简体中文"
        case (.english, .speedUnit): "Speed Unit"
        case (.english, .oneHour): "1 Hour"
        case (.english, .twentyFourHours): "24 Hours"
        case (.english, .sevenDays): "7 Days"
        case (.english, .totalDownload): "Downloaded"
        case (.english, .totalUpload): "Uploaded"
        case (.english, .peakDownload): "Download Peak"
        case (.english, .peakUpload): "Upload Peak"
        case (.english, .clearHistory): "Clear History"
        case (.english, .clearHistoryConfirmation): "This permanently clears all traffic history stored on this Mac. Other preferences are unchanged."
        case (.english, .cancel): "Cancel"
        case (.english, .confirmClear): "Clear"
        case (.english, .upload): "Upload"
        case (.english, .uploadOnly): "Upload Only"
        }
    }

    private let defaults: UserDefaults

    private func synchronizeBundleLanguage() {
        defaults.set([language.rawValue], forKey: Keys.appleLanguages)
    }
}
