import AppKit
import CodexAuthCore
import Darwin
import Observation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class AppModel {
    static let autoSwitchNotificationCategory = "CODEX_AUTH_BAR_AUTO_SWITCH"
    static let autoSwitchNotificationAction = "SWITCH_AND_RESTART"
    private(set) var accounts: [AccountRecord] = []
    private(set) var activeAccountKey: AccountKey?
    private(set) var previousAccountKey: AccountKey?
    private(set) var activeAccountActivatedAtMilliseconds: Int64?
    private(set) var profiles: [ProfileName] = []
    private(set) var supportsProfiles = false
    var selectedProfile: ProfileName?
    var isLoading = false
    var statusMessage = ""
    var errorMessage: String?
    var searchText = ""
    var diagnosticsText = "Diagnostics have not been started."
    var diagnosticsRunning = false
    var loginOutput = ""
    var loginInProgress = false
    var operationReport = ""

    let home: CodexHome
    private let repository: AccountRepository
    private let profileStore: ProfileStore
    private let usageService: ChatGPTUsageService
    private let processController: CodexProcessController
    private let codextManager = CodextManager()
    private var lastAutoSwitchActiveRefresh = Date.distantPast
    private var fileWatcher: DirectoryWatcher?

    init() {
        AppPreferenceStore.loadIntoUserDefaults()
        let preference = UserDefaults.standard.string(forKey: "codexHome").flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
        }
        home = CodexHome.resolve(preference: preference)
        repository = AccountRepository(home: home)
        profileStore = ProfileStore(home: home)
        usageService = ChatGPTUsageService(home: home)
        processController = CodexProcessController(home: home)
        if let raw = UserDefaults.standard.string(forKey: "selectedProfile") { selectedProfile = ProfileName(raw) }
        Task { await start() }
    }

    var activeAccount: AccountRecord? { accounts.first { $0.accountKey == activeAccountKey } }
    var hasError: Bool { errorMessage != nil }
    var filteredAccounts: [AccountRecord] {
        guard !searchText.isEmpty else { return accounts }
        return accounts.filter {
            [$0.alias, $0.email, $0.accountName ?? "", $0.accountKey.rawValue]
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    func start() async {
        var recoveryResult: RecoveryResult?
        var recoveryError: String?
        do { recoveryResult = try await RegistryStore(home: home).recoverPendingTransaction() }
        catch { recoveryError = "Recovery: \(error.localizedDescription)" }
        await reload()
        if let capabilities = try? await processController.capabilities() {
            supportsProfiles = capabilities.supportsProfiles
        }
        if let recoveryError {
            errorMessage = recoveryError
        } else if recoveryResult == .manualInterventionRequired {
            errorMessage = "Recovery stopped because auth.json contains unknown external changes. No files were overwritten."
        } else if recoveryResult == .registryReconciled {
            statusMessage = "Recovered an interrupted account switch"
        }
        do {
            try FileManager.default.createDirectory(at: home.accounts, withIntermediateDirectories: true)
            fileWatcher = try DirectoryWatcher(url: home.accounts) { [weak self] in
                Task { @MainActor in await self?.reload() }
            }
        } catch { errorMessage = error.localizedDescription }
        Task { await autoSwitchLoop() }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let state = try await repository.state(refresh: .stored)
            accounts = state.registry.accounts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            activeAccountKey = state.registry.activeAccountKey
            previousAccountKey = state.registry.previousActiveAccountKey
            activeAccountActivatedAtMilliseconds = state.registry.activeAccountActivatedAtMilliseconds
            profiles = try await profileStore.list()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchAccount(_ key: AccountKey, restart: Bool = true) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await processController.ensureFileCredentialStore()
            let wasRunning = await processController.isDesktopRunning()
            if restart, wasRunning { try await processController.terminateDesktopApp(timeout: .seconds(10)) }
            do {
                _ = try await repository.switchAccount(to: key)
            } catch {
                if restart, wasRunning { try? await processController.launchDesktopApp(CodexLaunchRequest(codexHome: home.root)) }
                throw error
            }
            if restart, wasRunning { try await processController.launchDesktopApp(CodexLaunchRequest(codexHome: home.root)) }
            statusMessage = restart && wasRunning ? "Switched and restarted Codex" : "Account switched"
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchPrevious() async {
        guard let previousAccountKey else { return }
        await switchAccount(previousAccountKey)
    }

    func refreshUsage(localOnly: Bool = false, activeOnly: Bool = false) async {
        let remoteRefreshEnabled = UserDefaults.standard.object(forKey: "apiRefreshEnabled") as? Bool ?? true
        if !localOnly, !remoteRefreshEnabled {
            statusMessage = "Remote usage refresh is disabled in Settings"
            return
        }
        isLoading = true
        defer { isLoading = false }
        let targets = activeOnly ? accounts.filter { $0.accountKey == activeAccountKey } : accounts
        if localOnly {
            do {
                if let activeAccountKey, let event = try LocalUsageScanner.newest(home: home, activatedAtMilliseconds: activeAccountActivatedAtMilliseconds) {
                    try await repository.updateLocalUsage(event, for: activeAccountKey)
                }
            } catch { errorMessage = error.localizedDescription }
        } else {
            var failures: [String] = []
            await withTaskGroup(of: (AccountKey, UsageFetchResult).self) { group in
                for account in targets { group.addTask { (account.accountKey, await self.usageService.usage(for: account)) } }
                for await (key, result) in group {
                    switch result {
                    case let .success(snapshot): try? await repository.updateUsage(snapshot, for: key)
                    case let .status(code): failures.append("HTTP \(code)")
                    case .missingAuth: failures.append("MissingAuth")
                    case let .transport(reason): failures.append(reason)
                    }
                }
            }
            try? await repository.refreshAccountNames(using: usageService)
            statusMessage = failures.isEmpty
                ? "Usage refreshed"
                : "Usage refreshed with: \(Dictionary(grouping: failures, by: { $0 }).map { "\($0.key) ×\($0.value.count)" }.sorted().joined(separator: ", "))"
        }
        await reload()
    }

    func importFile(_ url: URL, format: ImportFormat = .automatic) async {
        do {
            let report = try await repository.importAccounts(ImportRequest(source: url, format: format))
            statusMessage = "Imported \(report.importedAccountKeys.count) account(s)"
            operationReport = report.events.map {
                "\($0.outcome.rawValue)\t\($0.source)\t\($0.detail)"
            }.joined(separator: "\n")
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func exportAccounts(format: ExportFormat, to destination: URL?) async {
        do {
            let report = try await repository.exportAccounts(ExportRequest(destination: destination, format: format))
            statusMessage = "Exported \(report.exportedCount) account(s); skipped \(report.skippedCount)"
            operationReport = "Destination: \(report.destination.path)\nExported: \(report.exportedCount)\nSkipped: \(report.skippedCount)"
        } catch { errorMessage = error.localizedDescription }
    }

    func purgeRegistry() async {
        await importFile(home.accounts, format: .purge)
    }

    func cleanManagedFiles() async {
        do {
            let report = try await repository.clean()
            statusMessage = "Cleaned \(report.deletedFiles.count) stale file(s)"
            operationReport = report.deletedFiles.isEmpty ? "No stale files found." : report.deletedFiles.joined(separator: "\n")
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func recoverTransaction() async {
        do {
            let result = try await RegistryStore(home: home).recoverPendingTransaction()
            statusMessage = "Recovery result: \(String(describing: result))"
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func remove(_ key: AccountKey) async {
        do {
            let report = try await repository.remove([key])
            operationReport = "Removed: \(report.removedAccountKeys.map(\.rawValue).joined(separator: ", "))\nPromoted: \(report.promotedAccountKey?.rawValue ?? "none")"
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func updateAlias(_ alias: String, for key: AccountKey) async {
        do { try await repository.setAlias(alias, for: key); await reload() } catch { errorMessage = error.localizedDescription }
    }

    func chooseProfile(_ profile: ProfileName?) {
        selectedProfile = profile
        UserDefaults.standard.set(profile?.rawValue, forKey: "selectedProfile")
        persistSettings()
    }

    func persistSettings() {
        do { try AppPreferenceStore.saveFromUserDefaults() }
        catch { errorMessage = "Settings: \(error.localizedDescription)" }
    }

    func createProfile(named rawName: String) async {
        guard let name = ProfileName(rawName) else {
            errorMessage = "Profile names may contain only letters, digits, underscore, and hyphen."
            return
        }
        do { try await profileStore.create(name); chooseProfile(name); await reload() }
        catch { errorMessage = error.localizedDescription }
    }

    func renameProfile(_ profile: ProfileName, to rawName: String) async {
        guard let newName = ProfileName(rawName) else {
            errorMessage = "Profile names may contain only letters, digits, underscore, and hyphen."
            return
        }
        do {
            try await profileStore.rename(profile, to: newName)
            if selectedProfile == profile { chooseProfile(newName) }
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteProfile(_ profile: ProfileName) async {
        do {
            try await profileStore.delete(profile)
            if selectedProfile == profile { chooseProfile(nil) }
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func openProfile(_ profile: ProfileName) async {
        NSWorkspace.shared.open(await profileStore.profileURL(profile))
    }

    func revealProfile(_ profile: ProfileName) async {
        NSWorkspace.shared.activateFileViewerSelecting([await profileStore.profileURL(profile)])
    }

    func copyProfileCommand(_ profile: ProfileName) async {
        do {
            let capabilities = try await processController.capabilities()
            guard capabilities.supportsProfiles else { throw ProcessError.profileUnsupported }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(TerminalCommandBuilder.command(codex: capabilities.executable, profile: profile), forType: .string)
            statusMessage = "Command copied"
        } catch { errorMessage = error.localizedDescription }
    }

    func removeLegacyLaunchAgent() async {
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/com.loongphy.codex-auth.auto.plist")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plist.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        do {
            if FileManager.default.fileExists(atPath: plist.path) { try FileManager.default.removeItem(at: plist) }
            statusMessage = "Legacy LaunchAgent removed"
        } catch { errorMessage = error.localizedDescription }
    }

    func launchCLI() async {
        guard let selectedProfile, supportsProfiles else {
            errorMessage = "The installed Codex CLI does not support --profile. Update Codex to enable profile launch."
            return
        }
        do {
            let capabilities = try await processController.capabilities()
            guard capabilities.supportsProfiles else { throw ProcessError.profileUnsupported }
            try await processController.launchTerminal(profile: selectedProfile)
        } catch { errorMessage = error.localizedDescription }
    }

    func login(deviceCode: Bool) async {
        loginInProgress = true
        loginOutput = "Starting Codex login…"
        defer { loginInProgress = false }
        do {
            let artifact = try await processController.performLogin(deviceCode ? .deviceCode : .browser) { [weak self] output in
                Task { @MainActor in self?.loginOutput = output }
            }
            defer { try? FileManager.default.removeItem(at: artifact.authURL) }
            _ = try await repository.importAccounts(ImportRequest(source: artifact.authURL, activate: true))
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func login(apiKey: String) async {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let artifact = try await processController.performLogin(.apiKey(apiKey))
            defer { try? FileManager.default.removeItem(at: artifact.authURL) }
            _ = try await repository.importAccounts(ImportRequest(source: artifact.authURL, activate: true))
            statusMessage = "API key account added"
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func cancelLogin() async {
        await processController.cancelLogin()
    }

    func launchCodext() async {
        do {
            let cli = try await codextManager.installedCLI()
            if await processController.isDesktopRunning() { try await processController.terminateDesktopApp(timeout: .seconds(10)) }
            try await processController.launchDesktopApp(CodexLaunchRequest(codexHome: home.root, cliPath: cli))
            statusMessage = "Codex launched with verified codext"
        } catch { errorMessage = error.localizedDescription }
    }

    func launchCodextDiagnostics() async {
        do {
            let cli = try await codextManager.installedCLI()
            if await processController.isDesktopRunning() {
                try await processController.terminateDesktopApp(timeout: .seconds(10))
            }
            let artifact = try await processController.launchDiagnostics(cliPath: cli)
            diagnosticsRunning = true
            diagnosticsText = "Diagnostics session started. Waiting for output…"
            while await processController.diagnosticsAreRunning(artifact) {
                diagnosticsText = (try? await processController.diagnosticOutput(artifact)) ?? diagnosticsText
                try? await Task.sleep(for: .seconds(1))
            }
            diagnosticsText = await processController.finishDiagnostics(artifact)
            diagnosticsRunning = false
        } catch {
            diagnosticsRunning = false
            errorMessage = error.localizedDescription
        }
    }

    private func autoSwitchLoop() async {
        while !Task.isCancelled {
            let storedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
            let interval = storedInterval == 0 ? 60 : max(5, storedInterval)
            try? await Task.sleep(for: .seconds(interval))
            guard UserDefaults.standard.bool(forKey: "autoSwitchEnabled") else { continue }
            await reload()
            let remoteEnabled = UserDefaults.standard.object(forKey: "apiRefreshEnabled") as? Bool ?? true
            if remoteEnabled, Date().timeIntervalSince(lastAutoSwitchActiveRefresh) >= 60,
               let active = activeAccount
            {
                await refreshAccountSilently(active)
                lastAutoSwitchActiveRefresh = .now
                await reload()
            }
            if remoteEnabled {
                let staleBefore = Int64(Date().timeIntervalSince1970) - 60
                let registry = RegistryV4(activeAccountKey: activeAccountKey, accounts: accounts)
                if let stale = AutoSwitchPolicy().rankedCandidates(registry: registry)
                    .first(where: { ($0.lastUsageAt ?? .min) < staleBefore })
                {
                    await refreshAccountSilently(stale)
                    await reload()
                }
            }
            let thresholds = AutoSwitchThresholds(
                fiveHour: UserDefaults.standard.double(forKey: "autoSwitch5h") == 0 ? 10 : UserDefaults.standard.double(forKey: "autoSwitch5h"),
                weekly: UserDefaults.standard.double(forKey: "autoSwitchWeekly") == 0 ? 5 : UserDefaults.standard.double(forKey: "autoSwitchWeekly")
            )
            var registry = RegistryV4(activeAccountKey: activeAccountKey, accounts: accounts)
            guard AutoSwitchPolicy().decision(registry: registry, thresholds: thresholds) != nil else { continue }
            if remoteEnabled {
                for candidate in AutoSwitchPolicy().rankedCandidates(registry: registry).prefix(3) {
                    await refreshAccountSilently(candidate)
                }
                await reload()
                registry = RegistryV4(activeAccountKey: activeAccountKey, accounts: accounts)
            }
            guard let decision = AutoSwitchPolicy().decision(registry: registry, thresholds: thresholds) else { continue }
            if await processController.isDesktopRunning(), await processController.isManagedDesktopRunning() {
                await switchAccount(decision.target, restart: false)
            } else if await processController.isDesktopRunning() {
                let content = UNMutableNotificationContent()
                content.title = "Codex limit threshold reached"
                content.body = "Switch to \(accounts.first(where: { $0.accountKey == decision.target })?.displayName ?? "the best available account") and restart Codex."
                content.categoryIdentifier = Self.autoSwitchNotificationCategory
                content.userInfo = ["targetAccountKey": decision.target.rawValue]
                let center = UNUserNotificationCenter.current()
                if (try? await center.requestAuthorization(options: [.alert, .sound])) == true {
                    try? await center.add(UNNotificationRequest(identifier: "auto-switch", content: content, trigger: nil))
                }
            } else {
                await switchAccount(decision.target, restart: false)
            }
        }
    }

    private func refreshAccountSilently(_ account: AccountRecord) async {
        if case let .success(snapshot) = await usageService.usage(for: account) {
            try? await repository.updateUsage(snapshot, for: account.accountKey)
        }
    }
}

private final class DirectoryWatcher: @unchecked Sendable {
    private let descriptor: Int32
    private let source: DispatchSourceFileSystemObject

    init(url: URL, handler: @escaping @Sendable () -> Void) throws {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue(label: "com.mesteriis.CodexAuthBar.file-watcher")
        )
        source.setEventHandler(handler: handler)
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
    }

    deinit { source.cancel() }
}

private struct PersistedAppSettings: Codable {
    var codexHome: String?
    var codexCLIPath: String?
    var selectedProfile: String?
    var codextPath: String?
    var apiRefreshEnabled: Bool?
    var autoSwitchEnabled: Bool?
    var autoSwitch5h: Double?
    var autoSwitchWeekly: Double?
    var refreshInterval: Double?
}

private enum AppPreferenceStore {
    private static var url: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "CodexAuthBar/preferences.json")
    }

    static func loadIntoUserDefaults() {
        guard let url, let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(PersistedAppSettings.self, from: data)
        else { return }
        let defaults = UserDefaults.standard
        if let value = settings.codexHome { defaults.set(value, forKey: "codexHome") }
        if let value = settings.codexCLIPath { defaults.set(value, forKey: "codexCLIPath") }
        if let value = settings.selectedProfile { defaults.set(value, forKey: "selectedProfile") }
        if let value = settings.codextPath { defaults.set(value, forKey: "codextPath") }
        if let value = settings.apiRefreshEnabled { defaults.set(value, forKey: "apiRefreshEnabled") }
        if let value = settings.autoSwitchEnabled { defaults.set(value, forKey: "autoSwitchEnabled") }
        if let value = settings.autoSwitch5h { defaults.set(value, forKey: "autoSwitch5h") }
        if let value = settings.autoSwitchWeekly { defaults.set(value, forKey: "autoSwitchWeekly") }
        if let value = settings.refreshInterval { defaults.set(value, forKey: "refreshInterval") }
    }

    static func saveFromUserDefaults() throws {
        guard let url else { throw CocoaError(.fileWriteUnknown) }
        let defaults = UserDefaults.standard
        let settings = PersistedAppSettings(
            codexHome: defaults.string(forKey: "codexHome"),
            codexCLIPath: defaults.string(forKey: "codexCLIPath"),
            selectedProfile: defaults.string(forKey: "selectedProfile"),
            codextPath: defaults.string(forKey: "codextPath"),
            apiRefreshEnabled: defaults.object(forKey: "apiRefreshEnabled") as? Bool,
            autoSwitchEnabled: defaults.object(forKey: "autoSwitchEnabled") as? Bool,
            autoSwitch5h: defaults.object(forKey: "autoSwitch5h") as? Double,
            autoSwitchWeekly: defaults.object(forKey: "autoSwitchWeekly") as? Double,
            refreshInterval: defaults.object(forKey: "refreshInterval") as? Double
        )
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
