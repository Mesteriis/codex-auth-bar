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

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, enabled in
                    do { enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch { model.errorMessage = error.localizedDescription }
                }
                LabeledContent("Codex home", value: model.home.root.path)
            }
            Section("Usage API") {
                Toggle("Use remote usage and workspace APIs", isOn: $apiRefreshEnabled)
                Text("Access tokens are sent only to chatgpt.com. These backend endpoints are unofficial and may change.").font(.caption).foregroundStyle(.secondary)
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
    }
}
