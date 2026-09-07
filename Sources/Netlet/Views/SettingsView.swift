import SwiftUI

struct SettingsView: View {
    let monitor: NetworkSpeedMonitor
    let preferences: PreferencesStore
    let historyStore: TrafficHistoryStore
    let languageStore: LanguageStore
    let launchAtLoginManager: LaunchAtLoginManager
    let updateManager: UpdateManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 12) {
                LiveSpeedPreview(monitor: monitor, preferences: preferences, languageStore: languageStore)
                TrafficHistoryView(
                    historyStore: historyStore,
                    preferences: preferences,
                    languageStore: languageStore
                )
                preferencesPanel
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            settingsFooter
        }
        .frame(
            minWidth: 860,
            idealWidth: 920,
            minHeight: 700,
            idealHeight: 720
        )
        .background(.regularMaterial)
        .onAppear { launchAtLoginManager.retryRegistration() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Netlet")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)

            Spacer()

            Menu {
                languageButton(.simplifiedChinese, title: languageStore[.simplifiedChinese])
                languageButton(.english, title: languageStore[.english])
            } label: {
                Label(currentLanguageTitle, systemImage: "character.bubble")
            }
            .controlSize(.regular)
            .fixedSize()
            .help(languageStore[.language])

            if let url = URL(string: "https://github.com/hjingsuper/Netlet") {
                Link(destination: url) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var preferencesPanel: some View {
        VStack(spacing: 0) {
            settingRow(languageStore[.menuBarDisplay]) {
                Picker("", selection: menuDisplayBinding) {
                    Text(languageStore[.full]).tag(MenuDisplayStyle.full)
                    Text(languageStore[.compact]).tag(MenuDisplayStyle.compact)
                    Text(languageStore[.downloadOnly]).tag(MenuDisplayStyle.downloadOnly)
                    Text(languageStore[.uploadOnly]).tag(MenuDisplayStyle.uploadOnly)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            rowDivider

            settingRow(languageStore[.speedUnit]) {
                Picker("", selection: unitModeBinding) {
                    Text(languageStore[.bytes]).tag(SpeedUnitMode.bytes)
                    Text(languageStore[.bits]).tag(SpeedUnitMode.bits)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            rowDivider

            settingRow(languageStore[.decimalPlaces]) {
                Picker("", selection: decimalPlacesBinding) {
                    ForEach(DecimalPlaces.allCases) { option in
                        Text("\(option.rawValue)").tag(option)
                    }
                }
                .labelsHidden()
            }

            rowDivider

            settingRow(languageStore[.interface]) {
                Picker("", selection: interfaceSelectionBinding) {
                    Text(languageStore[.automatic]).tag("automatic")
                    if let unavailableSelection {
                        Text(
                            "\(unavailableSelection) · \(languageStore[.interfaceUnavailable])"
                        )
                        .tag("interface:\(unavailableSelection)")
                    }
                    if !monitor.availableInterfaces.isEmpty {
                        Divider()
                    }
                    ForEach(monitor.availableInterfaces) { interface in
                        Text("\(interface.localizedName) (\(interface.systemName))")
                            .tag("interface:\(interface.systemName)")
                    }
                }
                .labelsHidden()
            }
        }
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }

    private var settingsFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(languageStore[.launchAtLogin], isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    if let message = launchAtLoginStatusMessage {
                        HStack(spacing: 8) {
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.orange)

                            Button(languageStore[.retry]) {
                                launchAtLoginManager.retryRegistration()
                            }
                            .buttonStyle(.link)
                            .font(.caption2)
                        }
                    }
                }

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    Button(languageStore[.checkForUpdates]) {
                        updateManager.checkForUpdates()
                    }
                    .disabled(!updateManager.isAvailable)

                    Text("v\(appVersion)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(languageStore[.automaticUpdatesDescription])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Label {
                Text(languageStore[.disclaimer])
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 118)
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(width: 102, alignment: .leading)

            Spacer(minLength: 16)
            content()
                .frame(width: 380, alignment: .trailing)
        }
        .frame(minHeight: 40)
    }

    private func languageButton(_ language: AppLanguage, title: String) -> some View {
        Button {
            languageStore.setLanguage(language)
        } label: {
            if languageStore.language == language {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var currentLanguageTitle: String {
        languageStore.language == .simplifiedChinese
            ? languageStore[.simplifiedChinese]
            : languageStore[.english]
    }

    private var menuDisplayBinding: Binding<MenuDisplayStyle> {
        Binding(
            get: { preferences.menuDisplayStyle },
            set: { preferences.setMenuDisplayStyle($0) }
        )
    }

    private var unitModeBinding: Binding<SpeedUnitMode> {
        Binding(
            get: { preferences.speedUnitMode },
            set: { preferences.setSpeedUnitMode($0) }
        )
    }

    private var decimalPlacesBinding: Binding<DecimalPlaces> {
        Binding(
            get: { preferences.decimalPlaces },
            set: { preferences.setDecimalPlaces($0) }
        )
    }

    private var interfaceSelectionBinding: Binding<String> {
        Binding(
            get: { preferences.interfaceSelection.persistedValue },
            set: { preferences.setInterfaceSelection(InterfaceSelection(persistedValue: $0)) }
        )
    }

    private var unavailableSelection: String? {
        guard case let .named(name) = preferences.interfaceSelection else { return nil }
        return monitor.availableInterfaces.contains { $0.systemName == name } ? nil : name
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginManager.isEnabled },
            set: { launchAtLoginManager.setEnabled($0) }
        )
    }

    private var launchAtLoginStatusMessage: String? {
        switch launchAtLoginManager.status {
        case .disabled, .enabled:
            nil
        case .requiresApproval:
            languageStore[.launchAtLoginNeedsApproval]
        case .unavailable:
            languageStore[.launchAtLoginUnavailable]
        case .failed:
            languageStore[.launchAtLoginFailed]
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        guard let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String else { return version }
        return "\(version) (\(build))"
    }
}

private struct LiveSpeedPreview: View {
    let monitor: NetworkSpeedMonitor
    let preferences: PreferencesStore
    let languageStore: LanguageStore
    var body: some View {
        HStack(spacing: 14) {
            Label(languageStore[.appSubtitle], systemImage: "menubar.rectangle")
                .font(.headline)

            Spacer(minLength: 20)

            Text(
                SpeedFormatter.stableStatusTitle(
                    snapshot: monitor.snapshot,
                    style: preferences.menuDisplayStyle,
                    unitMode: preferences.speedUnitMode,
                    decimalPlaces: preferences.decimalPlaces,
                    scalePair: monitor.scalePair(for: preferences.speedUnitMode)
                )
            )
            .font(.system(size: 18, weight: .medium, design: .monospaced))
            .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }

}
