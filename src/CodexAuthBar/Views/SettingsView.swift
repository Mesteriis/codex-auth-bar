import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("apiRefreshEnabled") private var apiRefreshEnabled = true
    @AppStorage("autoSwitchEnabled") private var autoSwitchEnabled = false
    @AppStorage("autoSwitch5h") private var threshold5h = 10.0
    @AppStorage("autoSwitchWeekly") private var thresholdWeekly = 5.0
    @AppStorage("refreshInterval") private var refreshInterval = 60.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("codexHome") private var codexHomePreference = ""
    @AppStorage("codexCLIPath") private var codexCLIPath = ""

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, enabled in
                    do { enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch { model.errorMessage = error.localizedDescription }
                }
                LabeledContent("Current Codex home", value: model.home.root.path)
                TextField("Custom CODEX_HOME", text: $codexHomePreference)
                HStack {
                    Button("Choose…") { chooseCodexHome() }
                    Button("Use default") { codexHomePreference = "" }
                }
                Text("Changes to CODEX_HOME take effect after restarting Codex Auth Bar.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Codex CLI path", text: $codexCLIPath)
                HStack {
                    Button("Reveal config.toml") { model.revealCodexConfig() }
                    Button("Copy file credential setting") { model.copyFileCredentialSetting() }
                }
                Text("Account switching requires top-level cli_auth_credentials_store = \"file\". Codex Auth Bar never changes this setting automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Usage API") {
                Toggle("Use remote usage and workspace APIs", isOn: $apiRefreshEnabled)
                Text("Access tokens are sent only to chatgpt.com. These backend endpoints are unofficial and may change.").font(.caption).foregroundStyle(.secondary)
                Link("Security and API disclosure", destination: URL(string: "https://github.com/Mesteriis/codex-auth-bar#security-and-privacy")!)
            }
            Section("Automatic switching") {
                Toggle("Enable auto-switch monitoring", isOn: $autoSwitchEnabled)
                Slider(value: $threshold5h, in: 1...100, step: 1) { Text("5h threshold") }
                LabeledContent("5h threshold", value: "\(Int(threshold5h))%")
                Slider(value: $thresholdWeekly, in: 1...100, step: 1) { Text("Weekly threshold") }
                LabeledContent("Weekly threshold", value: "\(Int(thresholdWeekly))%")
                Stepper("Refresh every \(Int(refreshInterval)) seconds", value: $refreshInterval, in: 5...3600, step: 5)
            }
            Section("Experimental") {
                Button("Install verified codext and launch Codex") { Task { await model.launchCodext() } }
                Text("Pinned to codext-v0.144.1-a8c9398. The archive is accepted only when its SHA-256 matches the bundled manifest.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: apiRefreshEnabled) { _, _ in model.persistSettings() }
        .onChange(of: autoSwitchEnabled) { _, _ in model.persistSettings() }
        .onChange(of: threshold5h) { _, _ in model.persistSettings() }
        .onChange(of: thresholdWeekly) { _, _ in model.persistSettings() }
        .onChange(of: refreshInterval) { _, _ in model.persistSettings() }
        .onChange(of: codexHomePreference) { _, _ in model.persistSettings() }
        .onChange(of: codexCLIPath) { _, _ in model.persistSettings() }
    }

    private func chooseCodexHome() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        codexHomePreference = url.path
    }
}
