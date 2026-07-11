import CodexAuthCore
import SwiftUI

struct MenuBarPopover: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            usage
            TextField("Search accounts", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("CodexAuthBar.search")

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.filteredAccounts) { account in
                        AccountRow(account: account, active: account.accountKey == model.activeAccountKey) {
                            Task { await model.switchAccount(account.accountKey) }
                        }
                    }
                }
            }
            .frame(maxHeight: 240)

            profileControls
            Divider()
            HStack {
                Button("Previous") { Task { await model.switchPrevious() } }
                    .disabled(model.previousAccountKey == nil)
                Menu("Add") {
                    Button("Browser login") { Task { await model.login(deviceCode: false) } }
                    Divider()
                    Button("Device code, import, or API key…") { activate(); openWindow(id: "accounts") }
                }
                Menu("Refresh") {
                    Button("All via API") { Task { await model.refreshUsage() } }
                    Button("Active via API") { Task { await model.refreshUsage(activeOnly: true) } }
                    Button("Local only") { Task { await model.refreshUsage(localOnly: true, activeOnly: true) } }
                }
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }

            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            } else if !model.statusMessage.isEmpty {
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button("Manage…") { activate(); openWindow(id: "accounts") }
                    .accessibilityIdentifier("CodexAuthBar.manage")
                Button("Settings…") { activate(); openSettings() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 370)
        .task { await model.reload() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "person.crop.circle.fill").font(.title2)
            VStack(alignment: .leading) {
                Text(model.activeAccount.map { visibleName($0.displayName) } ?? "No active account").font(.headline).lineLimit(1)
                Text(model.activeAccount?.email ?? "Add or import an account").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let plan = model.activeAccount?.resolvedPlan { Text(plan.label).font(.caption).padding(.horizontal, 7).padding(.vertical, 3).background(.quaternary, in: Capsule()) }
        }
    }

    @ViewBuilder private var usage: some View {
        if let snapshot = model.activeAccount?.lastUsage {
            HStack(spacing: 10) {
                UsageGauge(title: "5h", window: snapshot.primary)
                UsageGauge(title: "Weekly", window: snapshot.secondary)
            }
        }
    }

    private var profileControls: some View {
        HStack {
            Picker("Profile", selection: Binding(
                get: { model.selectedProfile?.rawValue ?? "" },
                set: { model.chooseProfile(ProfileName($0)) }
            )) {
                Text("Base config").tag("")
                ForEach(model.profiles, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
            }
            .labelsHidden()
            Button("Launch CLI") { Task { await model.launchCLI() } }
                .disabled(model.selectedProfile == nil || !model.supportsProfiles)
                .help(model.supportsProfiles ? "Launch Codex CLI with the selected profile" : "Update Codex CLI to enable --profile")
        }
    }

    private func activate() { NSApp.activate(ignoringOtherApps: true) }
}

private struct AccountRow: View {
    let account: AccountRecord
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: active ? "checkmark.circle.fill" : "circle").foregroundStyle(active ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(visibleName(account.displayName)).lineLimit(1)
                    if account.displayName != account.email { Text(account.email).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                if let remaining = account.lastUsage?.primary?.remainingPercent() { Text("\(Int(remaining))%").font(.caption.monospacedDigit()) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
        .accessibilityLabel(Text("Switch to \(account.displayName)"))
    }
}

private struct UsageGauge: View {
    let title: String
    let window: RateLimitWindow?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.caption); Spacer(); Text(window.map { "\(Int($0.remainingPercent()))%" } ?? "—").font(.caption.monospacedDigit()) }
            ProgressView(value: window?.remainingPercent() ?? 0, total: 100)
            if let resetsAt = window?.resetsAt {
                Text(Date(timeIntervalSince1970: TimeInterval(resetsAt)), style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var accessibilityValue: String {
        guard let window else { return "Usage unavailable" }
        let remaining = Int(window.remainingPercent())
        if let resetsAt = window.resetsAt {
            return "\(remaining) percent remaining, resets \(Date(timeIntervalSince1970: TimeInterval(resetsAt)).formatted())"
        }
        return "\(remaining) percent remaining"
    }
}

private func visibleName(_ value: String) -> String {
    value.count > 30 ? String(value.prefix(29)) + "…" : value
}
