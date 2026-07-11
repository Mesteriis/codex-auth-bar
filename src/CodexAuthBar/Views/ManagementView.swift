import AppKit
import CodexAuthCore
import SwiftUI

struct ManagementView: View {
    @Bindable var model: AppModel
    @State private var accountSelection: AccountKey?
    @State private var profileSelection: ProfileName?
    @State private var alias = ""
    @State private var profileName = ""
    @State private var confirmAccountRemoval = false
    @State private var confirmProfileRemoval = false
    @State private var confirmPurge = false
    @State private var confirmClean = false
    @State private var confirmLegacyCleanup = false
    @State private var showAPIKeyLogin = false
    @State private var showLoginProgress = false
    @State private var apiKey = ""
    @AppStorage("codextPath") private var customCodextPath = ""
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TabView {
            accountsView
                .tabItem { Label("Accounts", systemImage: "person.2") }
            importExportView
                .tabItem { Label("Import/Export", systemImage: "square.and.arrow.down.on.square") }
            profilesView
                .tabItem { Label("Profiles", systemImage: "slider.horizontal.3") }
            maintenanceView
                .tabItem { Label("Recovery", systemImage: "cross.case") }
            experimentalView
                .tabItem { Label("Experimental", systemImage: "flask") }
        }
        .safeAreaInset(edge: .bottom) { statusBar }
        .task { await model.reload() }
        .alert("Remove account?", isPresented: $confirmAccountRemoval) {
            Button("Remove", role: .destructive) {
                if let accountSelection { Task { await model.remove(accountSelection) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The managed auth snapshot and matching account record will be deleted.") }
        .alert("Delete profile?", isPresented: $confirmProfileRemoval) {
            Button("Delete", role: .destructive) {
                if let profileSelection { Task { await model.deleteProfile(profileSelection) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The selected .config.toml profile will be deleted. Base config.toml is never changed.") }
        .alert("Rebuild account registry?", isPresented: $confirmPurge) {
            Button("Rebuild", role: .destructive) { Task { await model.purgeRegistry() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Registry metadata will be rebuilt from the newest valid managed snapshots and backups.") }
        .alert("Clean managed files?", isPresented: $confirmClean) {
            Button("Clean", role: .destructive) { Task { await model.cleanManagedFiles() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Only recognized stale snapshots and excess managed backups are eligible. The export backup directory is preserved.") }
        .alert("Remove legacy LaunchAgent?", isPresented: $confirmLegacyCleanup) {
            Button("Remove", role: .destructive) { Task { await model.removeLegacyLaunchAgent() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Unloads and removes only com.loongphy.codex-auth.auto.plist.") }
        .sheet(isPresented: $showAPIKeyLogin) { apiKeySheet }
        .sheet(isPresented: $showLoginProgress) { loginProgressSheet }
        .onChange(of: customCodextPath) { _, _ in model.persistSettings() }
    }

    private var accountsView: some View {
        NavigationSplitView {
            List(model.accounts, selection: $accountSelection) { account in
                VStack(alignment: .leading) {
                    Text(account.displayName.count > 30 ? String(account.displayName.prefix(29)) + "…" : account.displayName).lineLimit(1)
                    Text(account.email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .tag(account.accountKey)
            }
            .navigationTitle("Accounts")
            .toolbar {
                Button { importAccount() } label: { Label("Import", systemImage: "square.and.arrow.down") }
                Menu {
                    Button("Browser login") { beginLogin(deviceCode: false) }
                    Button("Device-code login") { beginLogin(deviceCode: true) }
                    Button("API key…") { showAPIKeyLogin = true }
                } label: { Label("Add", systemImage: "plus") }
            }
        } detail: {
            if let account = model.accounts.first(where: { $0.accountKey == accountSelection }) {
                accountDetail(account)
            } else {
                ContentUnavailableView("Select an account", systemImage: "person.crop.circle")
            }
        }
    }

    private func accountDetail(_ account: AccountRecord) -> some View {
        Form {
            Section("Identity") {
                LabeledContent("Email", value: account.email)
                LabeledContent("Account key", value: account.accountKey.rawValue)
                LabeledContent("Account ID", value: account.chatGPTAccountID)
                LabeledContent("User ID", value: account.chatGPTUserID)
                LabeledContent("Workspace", value: account.accountName ?? "—")
                LabeledContent("Plan", value: account.resolvedPlan?.label ?? "Unknown")
                LabeledContent("Authentication", value: account.authMode?.rawValue ?? "Unknown")
            }
            Section("Display") {
                TextField("Alias", text: $alias)
                    .onAppear { alias = account.alias }
                    .onChange(of: account.accountKey) { _, _ in alias = account.alias }
                Button("Save alias") { Task { await model.updateAlias(alias, for: account.accountKey) } }
            }
            if let usage = account.lastUsage {
                Section("Usage") {
                    LabeledContent("5h remaining", value: usage.primary.map { "\(Int($0.remainingPercent()))%" } ?? "—")
                    LabeledContent("Weekly remaining", value: usage.secondary.map { "\(Int($0.remainingPercent()))%" } ?? "—")
                    if let credits = usage.credits {
                        LabeledContent("Credits", value: credits.unlimited ? "Unlimited" : credits.balance ?? (credits.hasCredits ? "Available" : "None"))
                    }
                    if let resetCredits = usage.resetCredits {
                        LabeledContent("Reset credits", value: String(resetCredits))
                    }
                }
            }
            Section("Actions") {
                HStack {
                    Button("Switch & Restart") { Task { await model.switchAccount(account.accountKey) } }
                    Button("Switch only") { Task { await model.switchAccount(account.accountKey, restart: false) } }
                    Spacer()
                    Button("Remove", role: .destructive) { confirmAccountRemoval = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(account.displayName)
    }

    private var importExportView: some View {
        Form {
            Section("Import") {
                Button("Import auth file, JSON array, or folder…") { importAccount() }
                Text("Standard Codex auth and CPA JSON are detected automatically. Batch errors are reported without discarding successful entries.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Export") {
                HStack {
                    Button("Export standard…") { exportAccounts(format: .standard) }
                    Button("Export CPA…") { exportAccounts(format: .cpa) }
                }
                Text("CPA export skips API-key records. The default destination is CODEX_HOME/accounts/backup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            reportSection
        }
        .formStyle(.grouped)
        .padding()
    }

    private var profilesView: some View {
        HSplitView {
            List(model.profiles, id: \.self, selection: $profileSelection) { profile in
                Text(profile.rawValue).tag(profile)
            }
            .frame(minWidth: 220)
            Form {
                Section("Profile") {
                    TextField("Name", text: $profileName)
                    HStack {
                        Button("Create") { Task { await model.createProfile(named: profileName); profileName = "" } }
                        Button("Rename") {
                            if let profileSelection { Task { await model.renameProfile(profileSelection, to: profileName) } }
                        }
                        .disabled(profileSelection == nil)
                        Button("Delete", role: .destructive) { confirmProfileRemoval = true }
                            .disabled(profileSelection == nil)
                    }
                }
                Section("Open") {
                    HStack {
                        Button("Open in default editor") {
                            if let profileSelection { Task { await model.openProfile(profileSelection) } }
                        }
                        Button("Reveal in Finder") {
                            if let profileSelection { Task { await model.revealProfile(profileSelection) } }
                        }
                    }
                    .disabled(profileSelection == nil)
                }
                Section("Codex CLI") {
                    HStack {
                        Button("Launch") {
                            if let profileSelection { model.chooseProfile(profileSelection); Task { await model.launchCLI() } }
                        }
                        Button("Copy command") {
                            if let profileSelection { Task { await model.copyProfileCommand(profileSelection) } }
                        }
                    }
                    .disabled(profileSelection == nil || !model.supportsProfiles)
                    Text("Profiles affect only CLI sessions launched from Codex Auth Bar. Codex Desktop continues to use base config.toml.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 480)
        }
        .onChange(of: profileSelection) { _, profile in profileName = profile?.rawValue ?? "" }
    }

    private var maintenanceView: some View {
        Form {
            Section("Interrupted switch") {
                Button("Run transaction recovery") { Task { await model.recoverTransaction() } }
                Text("Known old or new auth hashes are reconciled. An unknown externally modified auth.json is never overwritten.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Registry recovery") {
                Button("Rebuild registry from snapshots…", role: .destructive) { confirmPurge = true }
                Button("Clean stale managed files…", role: .destructive) { confirmClean = true }
            }
            Section("Legacy maintenance") {
                Button("Remove Loongphy auto-switch LaunchAgent…", role: .destructive) { confirmLegacyCleanup = true }
                Text("This action is never run automatically.").font(.caption).foregroundStyle(.secondary)
            }
            reportSection
        }
        .formStyle(.grouped)
        .padding()
    }

    private var experimentalView: some View {
        Form {
            Section("Verified codext") {
                Button("Install pinned codext and launch Codex") { Task { await model.launchCodext() } }
                Button("Launch with diagnostics…") {
                    openWindow(id: "diagnostics")
                    Task { await model.launchCodextDiagnostics() }
                }
                Text("Pinned to codext-v0.144.1-a8c9398. HTTPS origin, archive contents, size, and SHA-256 are verified before installation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Custom executable") {
                TextField("Path to codext", text: $customCodextPath)
                Button("Choose executable…") { chooseCodext() }
                Text("Custom executables are user-trusted and are not covered by the pinned manifest verification.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var statusBar: some View {
        HStack {
            if model.isLoading { ProgressView().controlSize(.small) }
            Text(model.errorMessage ?? model.statusMessage)
                .font(.caption)
                .foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.red)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var reportSection: some View {
        if !model.operationReport.isEmpty {
            Section("Last report") {
                ScrollView([.horizontal, .vertical]) {
                    Text(model.operationReport)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 80, maxHeight: 180)
            }
        }
    }

    private var apiKeySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add API key account").font(.title2.bold())
            Text("The key is passed to Codex through standard input and is never placed in command arguments or logs.")
                .foregroundStyle(.secondary)
            SecureField("API key", text: $apiKey).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { apiKey = ""; showAPIKeyLogin = false }
                Button("Add") {
                    let submitted = apiKey
                    apiKey = ""
                    showAPIKeyLogin = false
                    Task { await model.login(apiKey: submitted) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 430)
    }

    private var loginProgressSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Codex login").font(.title2.bold())
                Spacer()
                if model.loginInProgress { ProgressView().controlSize(.small) }
            }
            Text("Follow the browser or device-code instructions below. Closing this window does not cancel an active Codex login.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(model.loginOutput)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 220)
            HStack {
                if model.loginInProgress {
                    Button("Cancel login", role: .destructive) { Task { await model.cancelLogin() } }
                }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.loginOutput, forType: .string)
                }
                Spacer()
                Button("Close") { showLoginProgress = false }
            }
        }
        .padding(24)
        .frame(width: 580, height: 390)
    }

    private func importAccount() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.importFile(url) }
    }

    private func exportAccounts(format: ExportFormat) {
        let panel = NSOpenPanel()
        panel.title = "Choose export directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return }
        Task { await model.exportAccounts(format: format, to: panel.url) }
    }

    private func chooseCodext() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customCodextPath = url.path
    }

    private func beginLogin(deviceCode: Bool) {
        showLoginProgress = true
        Task { await model.login(deviceCode: deviceCode) }
    }
}

struct DiagnosticsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Codex diagnostics").font(.title2.bold())
                Spacer()
                if model.diagnosticsRunning { ProgressView().controlSize(.small) }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.diagnosticsText, forType: .string)
                }
            }
            Text("Tokens, JWTs, and API keys are redacted before this output is displayed.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(model.diagnosticsText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding()
    }
}
